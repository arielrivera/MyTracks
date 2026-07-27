import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import os.log

private func appLog(_ message: String) {
    os_log("%{public}@", log: .default, type: .debug, "[ArielSplitter] \(message)")
}

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var audioFileInfo: AudioFileInfo?
    @Published var stemTracks: [StemTrack] = []
    @Published var separationState: SeparationState = .idle
    @Published var outputDirectory: URL?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    // MARK: - Audio Engine
    private var audioEngine: AudioEngineManager?
    private var separationEngine: SeparationEngine?
    private var playbackTimer: Timer?
    
    // MARK: - Computed Properties
    var hasAudioFile: Bool { audioFileInfo != nil }
    
    var selectedStems: [StemTrack] {
        stemTracks.filter { $0.isSelected && $0.isAvailable }
    }
    
    var hasSelection: Bool { !selectedStems.isEmpty }
    
    var canStartSeparation: Bool {
        hasAudioFile && hasSelection && !separationState.isActive && outputDirectory != nil
    }
    
    var allSelected: Bool {
        stemTracks.filter(\.isAvailable).allSatisfy(\.isSelected)
    }
    
    var anySelected: Bool {
        stemTracks.filter(\.isAvailable).contains(where: \.isSelected)
    }
    
    // MARK: - Initialization
    init() {
        setupDefaultOutputDirectory()
        setupDefaultTracks()
    }
    
    private func setupDefaultOutputDirectory() {
        let defaultURL = URL(fileURLWithPath: "/Users/arielrivera/Downloads/ariels_splitter_output")
        outputDirectory = defaultURL
        try? FileManager.default.createDirectory(at: defaultURL, withIntermediateDirectories: true)
    }
    
    private func setupDefaultTracks() {
        stemTracks = StemCategory.allCases
            .filter { $0.parentCategory == nil || $0 == .other }
            .map { StemTrack(category: $0, isSelected: true) }
    }
    
    // MARK: - File Management
    func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav, .mp3, .m4a, .aiff, .flac]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an audio file to separate"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadAudioFile(url: url)
    }
    
    func loadAudioFile(url: URL) {
        appLog("loadAudioFile(url: \(url.path))")
        Task { @MainActor in
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let asset = AVAsset(url: url)
                let duration = try await asset.load(.duration).seconds
                let tracks = try await asset.load(.tracks)
                
                guard let audioTrack = tracks.first(where: { $0.mediaType == .audio }) else {
                    self.separationState = .failed("No audio track found in file")
                    return
                }
                
                let formatDescriptions = try await audioTrack.load(.formatDescriptions)
                let audioFormat = formatDescriptions.first
                
                var sampleRate: Double = 44100
                var channels: Int = 2
                
                if let formatDesc = audioFormat {
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                    if let asbd = asbd?.pointee {
                        sampleRate = asbd.mSampleRate
                        channels = Int(asbd.mChannelsPerFrame)
                    }
                }
                
                let fileInfo = AudioFileInfo(
                    url: url,
                    name: url.lastPathComponent,
                    format: url.pathExtension.uppercased(),
                    duration: duration,
                    sampleRate: sampleRate,
                    channels: channels
                )
                
                appLog("loadAudioFile succeeded: \(fileInfo.name)")
                self.audioFileInfo = fileInfo
                self.duration = duration
                self.separationState = .idle
                self.setupAudioEngine(AudioEngineManager(fileURL: url))
                
            } catch {
                appLog("loadAudioFile failed: \(error.localizedDescription)")
                self.separationState = .failed("Could not load audio file: \(error.localizedDescription)")
            }
        }
    }
    
    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where to save separated tracks"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectory = url
    }
    
    // MARK: - Track Selection
    func selectAllTracks() {
        for i in stemTracks.indices where stemTracks[i].isAvailable {
            stemTracks[i].isSelected = true
        }
    }
    
    func deselectAllTracks() {
        for i in stemTracks.indices where stemTracks[i].isAvailable {
            stemTracks[i].isSelected = false
        }
    }
    
    func toggleTrack(_ track: StemTrack) {
        guard let index = stemTracks.firstIndex(of: track) else { return }
        stemTracks[index].isSelected.toggle()
    }
    
    // MARK: - Separation
    func startSeparation() {
        appLog("startSeparation() called")
        guard let fileInfo = audioFileInfo, let outputDir = outputDirectory else {
            appLog("Cannot start separation: missing fileInfo or outputDir")
            return
        }
        
        let selectedCategories = selectedStems.map { $0.category }
        appLog("Selected categories: \(selectedCategories)")
        separationState = .separating(progress: 0, currentStem: "Initializing...", resources: nil)
        
        Task { @MainActor in
            do {
                appLog("Creating SeparationEngine")
                let engine = SeparationEngine()
                self.separationEngine = engine
                
                appLog("Calling engine.separate")
                try await engine.separate(
                    fileURL: fileInfo.url,
                    categories: selectedCategories,
                    outputDirectory: outputDir,
                    progressHandler: { progress, stem, resources in
                        Task { @MainActor in
                            self.separationState = .separating(progress: progress, currentStem: stem, resources: resources)
                        }
                    }
                )
                appLog("engine.separate returned")
                
                for i in self.stemTracks.indices {
                    let category = self.stemTracks[i].category
                    let fileName = "\(category.rawValue).wav"
                    let fileURL = outputDir.appendingPathComponent(fileName)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        self.stemTracks[i].fileURL = fileURL
                    }
                }
                
                self.separationState = .completed
                // Stop old engine before creating new one
                self.audioEngine?.stop()
                let newEngine = AudioEngineManager(fileURL: fileInfo.url)
                self.setupAudioEngine(newEngine)
                try await newEngine.loadStems(from: outputDir, tracks: self.stemTracks.filter { $0.fileURL != nil })
                
            } catch {
                self.separationState = .failed(error.localizedDescription)
            }
        }
    }
    
    func cancelSeparation() {
        separationEngine?.cancel()
        separationState = .cancelled
    }
    
    func reset() {
        audioEngine?.stop()
        audioEngine = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioFileInfo = nil
        stemTracks = []
        separationState = .idle
        outputDirectory = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        setupDefaultTracks()
    }
    
    private func setupAudioEngine(_ engine: AudioEngineManager) {
        audioEngine = engine
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    // MARK: - Playback
    func togglePlayback() {
        guard let engine = audioEngine else { return }
        
        if isPlaying {
            engine.pause()
        } else {
            engine.play()
            startPlaybackTimer()
        }
    }
    
    func seek(to time: TimeInterval) {
        audioEngine?.seek(to: time)
        currentTime = time
    }
    
    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let engine = self.audioEngine else { return }
                self.currentTime = engine.currentTime
                self.isPlaying = engine.isCurrentlyPlaying
                
                if !self.isPlaying {
                    self.playbackTimer?.invalidate()
                    self.playbackTimer = nil
                }
            }
        }
    }
    
    func setVolume(for track: StemTrack, volume: Float) {
        guard let index = stemTracks.firstIndex(of: track) else { return }
        stemTracks[index].volume = volume
        audioEngine?.setVolume(for: track.category, volume: volume)
    }
    
    func toggleMute(for track: StemTrack) {
        guard let index = stemTracks.firstIndex(of: track) else { return }
        stemTracks[index].isMuted.toggle()
        audioEngine?.setMute(for: track.category, isMuted: stemTracks[index].isMuted)
    }
    
    func toggleSolo(for track: StemTrack) {
        guard let index = stemTracks.firstIndex(of: track) else { return }
        stemTracks[index].isSolo.toggle()
        
        let soloedCategories = Set(stemTracks.filter(\.isSolo).map(\.category))
        for i in stemTracks.indices {
            let shouldMute = !soloedCategories.isEmpty && !soloedCategories.contains(stemTracks[i].category)
            audioEngine?.setMute(for: stemTracks[i].category, isMuted: shouldMute)
        }
    }
    
    // MARK: - Export
    func exportStem(_ track: StemTrack) {
        guard let fileURL = track.fileURL else { return }
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileURL.lastPathComponent
        panel.allowedContentTypes = [.wav]
        
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        } catch {
            separationState = .failed("Could not export: \(error.localizedDescription)")
        }
    }
    
    func exportMixedTrack() {
        guard outputDirectory != nil else { return }
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Mixed Track.wav"
        panel.allowedContentTypes = [.wav]
        
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        
        Task { @MainActor in
            do {
                try await self.audioEngine?.exportMix(to: destinationURL, tracks: self.stemTracks)
            } catch {
                self.separationState = .failed("Could not export mix: \(error.localizedDescription)")
            }
        }
    }
    
    func openResultsFolder() {
        guard let outputDir = outputDirectory else { return }
        NSWorkspace.shared.open(outputDir)
    }
}

// MARK: - UTType Extensions
extension UTType {
    static let wav = UTType(filenameExtension: "wav") ?? .audio
    static let mp3 = UTType(filenameExtension: "mp3") ?? .audio
    static let m4a = UTType(filenameExtension: "m4a") ?? .audio
    static let aiff = UTType(filenameExtension: "aiff") ?? .audio
    static let flac = UTType(filenameExtension: "flac") ?? .audio
}