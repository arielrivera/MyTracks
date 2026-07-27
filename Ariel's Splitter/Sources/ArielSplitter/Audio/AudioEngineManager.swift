import Foundation
import AVFoundation

/// Manages audio playback and mixing using AVAudioEngine.
/// All methods must be called from the main actor.
@MainActor
class AudioEngineManager: ObservableObject {
    private let engine = AVAudioEngine()
    private var playerNodes: [StemCategory: AVAudioPlayerNode] = [:]
    private var audioFiles: [StemCategory: AVAudioFile] = [:]
    private var isPlaying = false
    private var seekTime: TimeInterval = 0
    private var startTime: Date?
    private var timer: Timer?
    private var totalDuration: TimeInterval = 0
    
    @Published var currentTime: TimeInterval = 0
    
    var duration: TimeInterval {
        totalDuration
    }
    
    var isCurrentlyPlaying: Bool {
        isPlaying
    }
    
    init(fileURL: URL? = nil) {
        // Do not start the engine here; it has no nodes yet and will fail
        // in environments without an audio output route. Start on demand in play().
    }
    
    func loadStems(from directory: URL, tracks: [StemTrack]) async throws {
        stop()
        
        for (_, node) in playerNodes {
            engine.detach(node)
        }
        playerNodes.removeAll()
        audioFiles.removeAll()
        
        var maxDuration: TimeInterval = 0
        
        for track in tracks {
            guard let fileURL = track.fileURL else { continue }
            
            let file = try AVAudioFile(forReading: fileURL)
            audioFiles[track.category] = file
            
            let duration = Double(file.length) / file.processingFormat.sampleRate
            maxDuration = max(maxDuration, duration)
            
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
            playerNode.volume = track.isMuted ? 0 : track.volume
            playerNodes[track.category] = playerNode
        }
        
        totalDuration = maxDuration
        currentTime = 0
        seekTime = 0
    }
    
    func play() {
        guard !playerNodes.isEmpty else { return }
        
        // Ensure engine is running
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("Failed to restart audio engine: \(error)")
                return
            }
        }
        
        // Stop any current playback first
        for (_, node) in playerNodes {
            node.stop()
        }
        
        // Schedule files from seek position
        for (category, node) in playerNodes {
            guard let file = audioFiles[category] else { continue }
            
            let sampleRate = file.processingFormat.sampleRate
            let framePosition = min(AVAudioFramePosition(seekTime * sampleRate), file.length - 1)
            file.framePosition = max(0, framePosition)
            
            node.scheduleFile(file, at: nil, completionHandler: nil)
        }
        
        // Play immediately (no scheduled start time)
        for (_, node) in playerNodes {
            node.play()
        }
        
        isPlaying = true
        startTime = Date().addingTimeInterval(-seekTime)
        
        startProgressTimer()
    }
    
    func pause() {
        for (_, node) in playerNodes {
            node.pause()
        }
        isPlaying = false
        timer?.invalidate()
        timer = nil
        
        if let start = startTime {
            seekTime = Date().timeIntervalSince(start)
        }
    }
    
    func stop() {
        for (_, node) in playerNodes {
            node.stop()
        }
        isPlaying = false
        seekTime = 0
        currentTime = 0
        timer?.invalidate()
        timer = nil
        startTime = nil
    }
    
    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, totalDuration))
        seekTime = clampedTime
        currentTime = clampedTime
        
        if isPlaying {
            play()
        }
    }
    
    func setVolume(for category: StemCategory, volume: Float) {
        playerNodes[category]?.volume = volume
    }
    
    func setMute(for category: StemCategory, isMuted: Bool) {
        playerNodes[category]?.volume = isMuted ? 0 : 1
    }
    
    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            var time = Date().timeIntervalSince(start)
            time = max(0, min(time, self.totalDuration))
            self.currentTime = time
            
            if time >= self.totalDuration {
                self.stop()
            }
        }
    }
    
    func exportMix(to url: URL, tracks: [StemTrack]) async throws {
        var mixFiles: [(AVAudioFile, Float)] = []
        
        for track in tracks where !track.isMuted {
            guard let fileURL = track.fileURL,
                  let file = try? AVAudioFile(forReading: fileURL) else { continue }
            mixFiles.append((file, track.volume))
        }
        
        guard !mixFiles.isEmpty else { return }
        
        let format = mixFiles[0].0.processingFormat
        let maxLength = mixFiles.map { $0.0.length }.max() ?? 0
        
        guard let outputFile = try? AVAudioFile(forWriting: url, settings: format.settings) else {
            throw NSError(domain: "AudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create output file"])
        }
        
        let bufferCapacity: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferCapacity) else {
            throw NSError(domain: "AudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create mix buffer"])
        }
        
        var framePosition: AVAudioFramePosition = 0
        
        while framePosition < maxLength {
            buffer.frameLength = min(bufferCapacity, AVAudioFrameCount(maxLength - framePosition))
            
            for channel in 0..<Int(format.channelCount) {
                if let floatData = buffer.floatChannelData?[channel] {
                    memset(floatData, 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
                }
            }
            
            for (file, volume) in mixFiles {
                let fileFrame = AVAudioFramePosition(framePosition)
                if fileFrame < file.length {
                    file.framePosition = fileFrame
                    if let tempBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferCapacity) {
                        try file.read(into: tempBuffer, frameCount: buffer.frameLength)
                        
                        for channel in 0..<Int(format.channelCount) {
                            guard let srcData = tempBuffer.floatChannelData?[channel],
                                  let dstData = buffer.floatChannelData?[channel] else { continue }
                            for frame in 0..<Int(buffer.frameLength) {
                                dstData[frame] += srcData[frame] * volume
                            }
                        }
                    }
                }
            }
            
            try outputFile.write(from: buffer)
            framePosition += AVAudioFramePosition(buffer.frameLength)
        }
    }
}