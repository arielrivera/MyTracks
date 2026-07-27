import Foundation

struct AudioFileInfo: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let format: String
    let duration: TimeInterval
    let sampleRate: Double
    let channels: Int
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedSampleRate: String {
        String(format: "%.1f kHz", sampleRate / 1000)
    }
    
    var formattedChannels: String {
        channels == 1 ? "Mono" : "Stereo"
    }
}