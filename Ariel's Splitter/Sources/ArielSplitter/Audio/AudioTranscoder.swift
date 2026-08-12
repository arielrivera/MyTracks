import Foundation
import os.log

private func transcodeLog(_ message: String) {
    os_log("%{public}@", log: .default, type: .debug, "[ArielSplitter Transcode] \(message)")
}

/// Converts audio between the formats the app offers, via ffmpeg.
///
/// ffmpeg is already a hard requirement for decoding input, so compression adds
/// no new dependency — but it is still located rather than assumed, since a GUI
/// app cannot see Homebrew's PATH.
enum AudioTranscoder {

    enum TranscodeError: LocalizedError {
        case ffmpegMissing
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegMissing:
                return "ffmpeg is needed to convert audio, and could not be found. Install it with: brew install ffmpeg"
            case .failed(let detail):
                return detail.isEmpty ? "Audio conversion failed." : "Audio conversion failed: \(detail)"
            }
        }
    }

    static var isAvailable: Bool { MediaToolLocator.locate(.ffmpeg) != nil }

    /// Convert `source` into `destination`, whose extension should match `format`.
    static func convert(
        source: URL,
        destination: URL,
        format: AudioFormat,
        bitrateKbps: Int
    ) throws {
        guard let ffmpeg = MediaToolLocator.locate(.ffmpeg) else {
            throw TranscodeError.ffmpegMissing
        }

        var arguments = ["-nostdin", "-loglevel", "error", "-y", "-i", source.path, "-vn"]
        arguments += format.encoderArguments(bitrateKbps: bitrateKbps)
        arguments.append(destination.path)

        let result = MediaToolLocator.run(ffmpeg, arguments)
        guard result.succeeded, FileManager.default.fileExists(atPath: destination.path) else {
            transcodeLog("Failed converting \(source.lastPathComponent): \(result.output)")
            throw TranscodeError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        transcodeLog("Converted \(source.lastPathComponent) -> \(destination.lastPathComponent)")
    }

    /// Convert in place: write the new file beside the original, then remove it.
    ///
    /// Used after separation, where the stems are written as WAV and then
    /// compressed to the configured format. The original is only deleted once
    /// the replacement exists, so a failed conversion leaves the WAV intact.
    static func convertReplacingOriginal(
        source: URL,
        format: AudioFormat,
        bitrateKbps: Int
    ) throws -> URL {
        let destination = source
            .deletingPathExtension()
            .appendingPathExtension(format.fileExtension)

        // Nothing to do if it is already in the requested format.
        guard destination != source else { return source }

        try convert(source: source, destination: destination, format: format, bitrateKbps: bitrateKbps)
        try? FileManager.default.removeItem(at: source)
        return destination
    }
}
