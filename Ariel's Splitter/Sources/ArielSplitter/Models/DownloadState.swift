import Foundation

/// What to pull down from a URL.
enum DownloadKind: String, CaseIterable, Identifiable, Equatable {
    case audio
    case video
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: return "Audio only"
        case .video: return "Video only"
        case .both: return "Audio + video"
        }
    }

    var iconName: String {
        switch self {
        case .audio: return "waveform"
        case .video: return "film"
        case .both: return "square.stack.3d.up"
        }
    }

    /// Whether a run of this kind produces an audio file we can hand to Demucs.
    var producesAudio: Bool { self != .video }
}

enum DownloadState: Equatable {
    case idle
    case preparing
    case downloading(progress: Double, detail: String)
    case postProcessing(detail: String)
    case completed(audioURL: URL?, videoURL: URL?)
    case cancelled
    case failed(DownloadFailure)

    var isActive: Bool {
        switch self {
        case .preparing, .downloading, .postProcessing: return true
        case .idle, .completed, .cancelled, .failed: return false
        }
    }

    var progressValue: Double {
        if case .downloading(let progress, _) = self { return progress }
        if case .postProcessing = self { return 1.0 }
        return 0
    }

    var statusText: String {
        switch self {
        case .idle: return "Ready"
        case .preparing: return "Contacting site..."
        case .downloading(let progress, let detail):
            let pct = Int((progress * 100).rounded())
            return detail.isEmpty ? "Downloading \(pct)%" : "Downloading \(pct)% — \(detail)"
        case .postProcessing(let detail): return detail.isEmpty ? "Processing..." : detail
        case .completed: return "Download complete"
        case .cancelled: return "Cancelled"
        case .failed(let failure): return failure.message
        }
    }
}

/// A download failure, carrying whether an out-of-date yt-dlp is the likely cause.
///
/// Extractors break whenever a site changes its player, and the fix is almost
/// always a newer yt-dlp — so that case is modelled explicitly rather than being
/// buried in an error string the UI cannot act on.
struct DownloadFailure: Equatable {
    let message: String
    let details: String
    let looksLikeOutdatedTool: Bool

    init(message: String, details: String = "", looksLikeOutdatedTool: Bool = false) {
        self.message = message
        self.details = details
        self.looksLikeOutdatedTool = looksLikeOutdatedTool
    }

    /// Signatures yt-dlp emits when a site has outrun the installed version.
    private static let staleExtractorSignatures = [
        "unable to extract",
        "player response",
        "nsig extraction failed",
        "signature extraction failed",
        "unable to download api page",
        "sign in to confirm",
        "this content isn't available",
        "failed to extract any player response",
        "requested format is not available",
        "confirm you're not a bot",
    ]

    static func fromToolOutput(_ output: String, exitCode: Int32) -> DownloadFailure {
        let lowered = output.lowercased()
        let stale = staleExtractorSignatures.contains { lowered.contains($0) }

        // yt-dlp prefixes real failures with "ERROR:"; surface that line rather
        // than the whole log, which is mostly routine progress chatter.
        let errorLine = output
            .components(separatedBy: .newlines)
            .last { $0.trimmingCharacters(in: .whitespaces).hasPrefix("ERROR:") }?
            .trimmingCharacters(in: .whitespaces)

        let headline = errorLine.map { line -> String in
            let stripped = line.hasPrefix("ERROR:") ? String(line.dropFirst(6)) : line
            return stripped.trimmingCharacters(in: .whitespaces)
        } ?? "Download failed (exit code \(exitCode))"

        return DownloadFailure(
            message: headline,
            details: output,
            looksLikeOutdatedTool: stale
        )
    }
}
