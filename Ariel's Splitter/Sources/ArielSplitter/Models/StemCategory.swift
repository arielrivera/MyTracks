import Foundation

enum StemCategory: String, CaseIterable, Identifiable, Codable {
    case vocals = "Vocals"
    case leadVocal = "Lead Vocal"
    case backingVocals = "Backing Vocals"
    case vocalEffects = "Vocal Effects"
    case noise = "Noise / Artifacts"
    case drums = "Drums"
    case kick = "Kick"
    case snare = "Snare"
    case toms = "Toms"
    case cymbals = "Cymbals"
    case bass = "Bass"
    case guitar = "Guitar"
    case acousticGuitar = "Acoustic Guitar"
    case electricGuitar = "Electric Guitar"
    case piano = "Piano & Keys"
    // Note: there is deliberately no "Other Instruments" category. htdemucs_6s
    // produces six sources — drums, bass, other, vocals, guitar, piano — with no
    // separate one for it, so it mapped to the same file as Piano & Keys. That
    // gave the mixer two rows playing identical audio, summed into a doubled
    // piano in playback and in every exported mix.
    case other = "Other"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .vocals: return "mic.fill"
        case .leadVocal: return "person.wave.2.fill"
        case .backingVocals: return "person.2.wave.2.fill"
        case .vocalEffects: return "waveform.badge.plus"
        case .noise: return "tornado"
        case .drums: return "circle.grid.cross.fill"
        case .kick: return "circle.fill"
        case .snare: return "circle.dashed"
        case .toms: return "circle.hexagongrid.fill"
        case .cymbals: return "sparkles"
        case .bass: return "guitars.fill"
        case .guitar: return "guitars"
        case .acousticGuitar: return "music.note"
        case .electricGuitar: return "bolt.fill"
        case .piano: return "pianokeys"
        case .other: return "ellipsis.circle.fill"
        }
    }
    
    var isAvailable: Bool {
        switch self {
        case .vocals, .drums, .bass, .guitar, .piano, .other:
            return true
        case .leadVocal, .backingVocals, .vocalEffects, .noise:
            return true
        case .kick, .snare, .toms, .cymbals:
            return true
        case .acousticGuitar, .electricGuitar:
            return true // htdemucs_6s supports guitar
        }
    }
    
    var unavailabilityReason: String? {
        return nil
    }
    
    var parentCategory: StemCategory? {
        switch self {
        case .leadVocal, .backingVocals, .vocalEffects, .noise:
            return .vocals
        case .kick, .snare, .toms, .cymbals:
            return .drums
        case .acousticGuitar, .electricGuitar:
            return .guitar
        default:
            return nil
        }
    }
    
    var isSubcategory: Bool {
        parentCategory != nil
    }
}