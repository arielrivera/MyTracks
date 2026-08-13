import Foundation

/// A file sitting in the output folder, for the Finder-style listing shown
/// under the mixer once a run has finished.
struct OutputFile: Identifiable, Equatable {
    let url: URL
    let size: Int64
    let modified: Date
    /// True when this file was produced by the run currently loaded, so it can
    /// be distinguished from stems left by earlier runs in the same folder.
    let isFromCurrentRun: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.uppercased() }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var formattedModified: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(modified) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "d MMM HH:mm"
        }
        return formatter.string(from: modified)
    }

    /// SF Symbol for the row, by broad file kind.
    var iconName: String {
        switch url.pathExtension.lowercased() {
        case "wav", "aiff", "flac", "alac": return "waveform"
        case "mp3", "m4a", "aac", "ogg", "opus": return "waveform.badge.minus"
        case "mp4", "mov", "mkv", "webm": return "film"
        default: return "doc"
        }
    }

    /// Audio and video extensions worth listing; anything else is noise.
    static let listedExtensions: Set<String> = [
        "wav", "aiff", "flac", "alac", "mp3", "m4a", "aac", "ogg", "opus",
        "mp4", "mov", "mkv", "webm",
    ]
}
