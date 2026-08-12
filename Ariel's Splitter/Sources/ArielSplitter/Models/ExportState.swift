import Foundation

enum ExportMode: String, CaseIterable, Identifiable, Equatable {
    case mixed
    case individual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: return "Current mix"
        case .individual: return "Individual stems"
        }
    }

    var detail: String {
        switch self {
        case .mixed: return "One file combining the stems at their current volume, with muted ones left out."
        case .individual: return "A separate file per stem, at full volume."
        }
    }

    var iconName: String {
        switch self {
        case .mixed: return "waveform"
        case .individual: return "square.stack.3d.up"
        }
    }
}

enum ExportState: Equatable {
    case configuring
    case exporting(progress: Double, detail: String)
    case done(count: Int, destination: URL)
    case failed(String)

    var isExporting: Bool {
        if case .exporting = self { return true }
        return false
    }
}

enum ExportError: LocalizedError {
    case noMixerLoaded
    case nothingSelected

    var errorDescription: String? {
        switch self {
        case .noMixerLoaded: return "The mixer isn't loaded, so there is nothing to mix down."
        case .nothingSelected: return "Select at least one stem to export."
        }
    }
}
