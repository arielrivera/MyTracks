import Foundation

struct StemTrack: Identifiable, Equatable {
    let id = UUID()
    let category: StemCategory
    var isSelected: Bool = true
    var volume: Float = 1.0
    var isMuted: Bool = false
    var isSolo: Bool = false
    var fileURL: URL?
    var isProcessing: Bool = false
    
    var displayName: String {
        category.rawValue
    }
    
    var isAvailable: Bool {
        category.isAvailable
    }
    
    var unavailabilityReason: String? {
        category.unavailabilityReason
    }
}