import Foundation
import os.log

private func downloadLog(_ message: String) {
    os_log("%{public}@", log: .default, type: .debug, "[ArielSplitter Download] \(message)")
}

/// Downloads media from a URL by driving yt-dlp as a subprocess.
///
/// yt-dlp is treated as an external tool the user owns, not a bundled dependency:
/// the app locates whatever copy is installed, reports clearly when it is missing,
/// and offers to update it in place when a site changes break extraction.
final class MediaDownloader: @unchecked Sendable {
    /// Emitted on stdout by our --progress-template so progress can be parsed
    /// without scraping yt-dlp's human-facing progress bar.
    private static let progressMarker = "@DL@"
    private static let stageMarker = "@STAGE@"

    private var isCancelled = false
    private var currentProcess: Process?
    private let lock = NSLock()

    func cancel() {
        lock.lock()
        isCancelled = true
        let process = currentProcess
        currentProcess = nil
        lock.unlock()
        process?.terminate()
    }

    // Synchronous accessors: NSLock must not be taken across an await, and
    // calling it directly from an async function is a Swift 6 error.
    private func resetCancellation() {
        lock.lock()
        isCancelled = false
        lock.unlock()
    }

    private func wasCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    private func setCurrentProcess(_ process: Process?) {
        lock.lock()
        currentProcess = process
        lock.unlock()
    }

    // MARK: - Availability

    struct Availability {
        let ytDlp: URL?
        let ffmpeg: URL?
        var isReady: Bool { ytDlp != nil }
    }

    static func checkAvailability() -> Availability {
        Availability(ytDlp: MediaToolLocator.locate(.ytDlp),
                     ffmpeg: MediaToolLocator.locate(.ffmpeg))
    }

    static func installedVersion(of toolURL: URL) -> String? {
        let result = MediaToolLocator.run(toolURL, ["--version"])
        guard result.succeeded else { return nil }
        let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    // MARK: - Download

    func download(
        urlString: String,
        kind: DownloadKind,
        destinationDirectory: URL,
        progressHandler: @escaping @Sendable (DownloadState) -> Void
    ) async throws -> (audio: URL?, video: URL?) {
        resetCancellation()

        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            throw DownloadError.failure(DownloadFailure(message: "Enter a video URL first."))
        }
        guard let parsed = URL(string: trimmedURL), parsed.scheme?.hasPrefix("http") == true else {
            throw DownloadError.failure(DownloadFailure(
                message: "That doesn't look like a web address.",
                details: "Expected a link starting with http:// or https://"
            ))
        }

        guard let ytDlp = MediaToolLocator.locate(.ytDlp) else {
            throw DownloadError.failure(DownloadFailure(
                message: "yt-dlp isn't installed, or the app can't find it.",
                details: """
                Install it with:  brew install yt-dlp

                If it is already installed, the app looks in /opt/homebrew/bin, \
                /usr/local/bin, ~/.local/bin and /opt/local/bin.
                """
            ))
        }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        // yt-dlp writes the final path here after any post-processing, which is
        // far more reliable than predicting the filename from the output template.
        let manifestURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("arielsplitter-download-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: manifestURL) }

        let arguments = Self.arguments(
            for: kind,
            url: trimmedURL,
            destination: destinationDirectory,
            manifest: manifestURL,
            ffmpeg: MediaToolLocator.locate(.ffmpeg)
        )

        downloadLog("Launching \(ytDlp.path) \(arguments.joined(separator: " "))")
        progressHandler(.preparing)

        let output = try await runDownload(executable: ytDlp, arguments: arguments, progressHandler: progressHandler)

        if wasCancelled() { throw DownloadError.cancelled }

        let produced = Self.readManifest(manifestURL)
        downloadLog("Produced files: \(produced.map(\.lastPathComponent))")

        var audioURL = produced.first { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
        let videoURL = produced.first { Self.videoExtensions.contains($0.pathExtension.lowercased()) }

        guard audioURL != nil || videoURL != nil else {
            throw DownloadError.failure(DownloadFailure.fromToolOutput(output, exitCode: 0))
        }

        // `both` downloads the video, then splits the audio off locally.
        if kind == .both, audioURL == nil, let videoURL {
            guard let ffmpeg = MediaToolLocator.locate(.ffmpeg) else {
                throw DownloadError.failure(DownloadFailure(
                    message: "Downloaded the video, but ffmpeg is needed to extract the audio.",
                    details: "Install it with:  brew install ffmpeg"
                ))
            }
            progressHandler(.postProcessing(detail: "Extracting audio..."))
            audioURL = try Self.extractAudio(from: videoURL, ffmpeg: ffmpeg)
        }

        return (audioURL, videoURL)
    }

    private func runDownload(
        executable: URL,
        arguments: [String],
        progressHandler: @escaping @Sendable (DownloadState) -> Void
    ) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        // NO_COLOR keeps ANSI escapes out of the lines we parse.
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        setCurrentProcess(process)

        let parseQueue = DispatchQueue(label: "com.arielsplitter.download-parser")

        // Every access below is guarded by stateLock.
        final class ParserState: @unchecked Sendable {
            var buffer = Data()
            var transcript = ""
            var lastProgress: Double = 0
        }
        let state = ParserState()
        let stateLock = NSLock()

        let handleLine: @Sendable (String) -> Void = { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            stateLock.lock()
            state.transcript += trimmed + "\n"
            stateLock.unlock()

            if trimmed.hasPrefix(Self.progressMarker) {
                let payload = String(trimmed.dropFirst(Self.progressMarker.count))
                let parts = payload.split(separator: "/")
                guard parts.count == 2,
                      let done = Double(parts[0]),
                      let total = Double(parts[1]), total > 0 else { return }

                let fraction = min(max(done / total, 0), 1)
                stateLock.lock()
                state.lastProgress = fraction
                stateLock.unlock()

                let detail = "\(Self.formatBytes(done)) of \(Self.formatBytes(total))"
                progressHandler(.downloading(progress: fraction, detail: detail))
            } else if trimmed.hasPrefix(Self.stageMarker) {
                progressHandler(.postProcessing(detail: "Converting audio..."))
            } else if trimmed.hasPrefix("[Merger]") {
                progressHandler(.postProcessing(detail: "Merging video and audio..."))
            } else if trimmed.hasPrefix("[ExtractAudio]") {
                progressHandler(.postProcessing(detail: "Extracting audio..."))
            } else if trimmed.hasPrefix("[FixupM4a]") || trimmed.hasPrefix("[VideoRemuxer]") {
                progressHandler(.postProcessing(detail: "Finalising file..."))
            } else {
                downloadLog(trimmed)
            }
        }

        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            parseQueue.async {
                stateLock.lock()
                state.buffer.append(data)
                var lines: [String] = []
                while let newline = state.buffer.range(of: Data([10])) {
                    let lineData = state.buffer.subdata(in: 0..<newline.lowerBound)
                    state.buffer.removeSubrange(0..<newline.upperBound)
                    if let line = String(data: lineData, encoding: .utf8) { lines.append(line) }
                }
                stateLock.unlock()
                lines.forEach(handleLine)
            }
        }

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                outputHandle.readabilityHandler = nil

                // Drain whatever is still buffered in the pipes.
                let remainingOut = outputHandle.readDataToEndOfFile()
                if let text = String(data: remainingOut, encoding: .utf8) {
                    text.components(separatedBy: .newlines).forEach(handleLine)
                }
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8) ?? ""

                stateLock.lock()
                let transcript = state.transcript + errorText
                stateLock.unlock()

                self.lock.lock()
                let cancelled = self.isCancelled
                self.currentProcess = nil
                self.lock.unlock()

                if cancelled {
                    continuation.resume(throwing: DownloadError.cancelled)
                } else if proc.terminationStatus != 0 {
                    let failure = DownloadFailure.fromToolOutput(transcript, exitCode: proc.terminationStatus)
                    downloadLog("Download failed: \(failure.message)")
                    continuation.resume(throwing: DownloadError.failure(failure))
                } else {
                    continuation.resume(returning: transcript)
                }
            }
        }
    }

    // MARK: - Arguments

    private static func arguments(
        for kind: DownloadKind,
        url: String,
        destination: URL,
        manifest: URL,
        ffmpeg: URL?
    ) -> [String] {
        var arguments: [String] = [
            "--newline",
            "--no-playlist",                 // a URL carrying &list= must not pull the whole playlist
            "--paths", destination.path,
            "-o", "%(title)s [%(id)s].%(ext)s",
            "--progress-template",
            "download:\(progressMarker)%(progress.downloaded_bytes)s/%(progress.total_bytes,progress.total_bytes_estimate)s",
            "--progress-template", "postprocess:\(stageMarker)%(progress.status)s",
            "--print-to-file", "after_move:filepath", manifest.path,
            "--no-simulate",                 // --print-to-file implies --simulate otherwise
            "--retries", "10",
            "--fragment-retries", "10",
        ]

        if let ffmpeg {
            arguments += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }

        switch kind {
        case .audio:
            arguments += [
                "-f", "bestaudio[ext=m4a]/bestaudio/best",
                "-x", "--audio-format", "m4a", "--audio-quality", "0",
            ]
        case .video, .both:
            // Prefer H.264 over AV1: YouTube serves intermittent 403s on AV1
            // streams, and H.264 also plays natively in QuickTime.
            //
            // `both` deliberately does not use --keep-video here. That flag
            // retains every intermediate stream, littering the folder with
            // .f137.mp4 / .f140.m4a files; extracting the audio from the merged
            // result afterwards is cleaner and costs no extra download.
            arguments += [
                "-f", "bestvideo[ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[ext=mp4]+bestaudio/bestvideo+bestaudio/best",
                "--merge-output-format", "mp4",
            ]
        }

        arguments.append(url)
        return arguments
    }

    /// Split the audio out of an already-downloaded video without re-encoding.
    ///
    /// Stream-copied, so it is near-instant and lossless; falls back to an AAC
    /// encode only if the source codec cannot live in an .m4a container.
    private static func extractAudio(from videoURL: URL, ffmpeg: URL) throws -> URL {
        let audioURL = videoURL.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: audioURL)

        let copyResult = MediaToolLocator.run(ffmpeg, [
            "-nostdin", "-loglevel", "error", "-y",
            "-i", videoURL.path, "-vn", "-c:a", "copy", audioURL.path,
        ])

        if copyResult.succeeded, FileManager.default.fileExists(atPath: audioURL.path) {
            return audioURL
        }

        downloadLog("Stream copy failed, re-encoding to AAC: \(copyResult.output)")
        try? FileManager.default.removeItem(at: audioURL)

        let encodeResult = MediaToolLocator.run(ffmpeg, [
            "-nostdin", "-loglevel", "error", "-y",
            "-i", videoURL.path, "-vn", "-c:a", "aac", "-b:a", "192k", audioURL.path,
        ])

        guard encodeResult.succeeded, FileManager.default.fileExists(atPath: audioURL.path) else {
            throw DownloadError.failure(DownloadFailure(
                message: "Downloaded the video, but could not extract its audio.",
                details: encodeResult.output
            ))
        }
        return audioURL
    }

    // MARK: - Results

    private static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "opus", "flac", "ogg", "aiff"]
    private static let videoExtensions: Set<String> = ["mp4", "mkv", "webm", "mov", "avi", "flv"]

    private static func readManifest(_ url: URL) -> [URL] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return contents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

enum DownloadError: Error, LocalizedError {
    case cancelled
    case failure(DownloadFailure)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Download cancelled"
        case .failure(let failure): return failure.message
        }
    }

    var failure: DownloadFailure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
