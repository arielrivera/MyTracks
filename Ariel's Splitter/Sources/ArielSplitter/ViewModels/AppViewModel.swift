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

    // MARK: - URL Download
    @Published var downloadURLString: String = ""
    @Published var downloadKind: DownloadKind = .audio
    @Published var downloadState: DownloadState = .idle
    @Published var updateState: UpdateState = .idle
    @Published var downloadDirectory: URL
    @Published var lastDownloadedVideoURL: URL?
    @Published var clipboardSuggestion: String?
    private var dismissedClipboardValue: String?

    /// True once there is a link to act on, which is what reveals the download
    /// options beneath the drop zone.
    var hasPendingDownloadURL: Bool {
        !downloadURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || downloadState.isActive
    }
    @Published var ytDlpPath: URL?
    @Published var ytDlpVersion: String?

    // MARK: - Audio format
    /// Format stems are written in. Persisted, since it is a standing
    /// preference rather than a per-run choice.
    @Published var stemFormat: AudioFormat {
        didSet { UserDefaults.standard.set(stemFormat.rawValue, forKey: "stemFormat") }
    }
    @Published var stemBitrate: AudioBitrate {
        didSet { UserDefaults.standard.set(stemBitrate.rawValue, forKey: "stemBitrate") }
    }

    // MARK: - Export
    @Published var isShowingExport = false
    @Published var exportMode: ExportMode = .mixed
    @Published var exportState: ExportState = .configuring
    @Published var exportSelection: Set<UUID> = []
    @Published var exportDestination: URL
    @Published var exportFormat: AudioFormat = .wav
    @Published var exportBitrate: AudioBitrate = .default

    // MARK: - Settings
    @Published var isShowingSettings = false
    @Published var ffmpegPath: URL?
    @Published var pythonInterpreter: PythonLocator.Interpreter?
    @Published var isCheckingEnvironment = false

    // MARK: - Audio Engine
    private var audioEngine: AudioEngineManager?
    private var separationEngine: SeparationEngine?
    private var mediaDownloader: MediaDownloader?
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
    
    /// Stage of the load → configure → separate → mix flow.
    ///
    /// The window shows only what belongs to the current stage: options that no
    /// longer apply are removed rather than left on screen, so there is nothing
    /// to fiddle with mid-run and nothing stale to read afterwards.
    enum WorkflowPhase {
        case needsFile      // nothing loaded yet
        case ready          // loaded; choose stems, output folder, then start
        case separating     // running; only progress and Cancel apply
        case finished       // done; mixer and export only
    }

    var workflowPhase: WorkflowPhase {
        guard hasAudioFile else { return .needsFile }
        if separationState.isActive { return .separating }
        if separationState == .completed { return .finished }
        // Cancelled and failed fall back to .ready so the run can be retried.
        return .ready
    }

    var urlValidation: URLValidator.Result {
        URLValidator.validate(downloadURLString)
    }

    var canStartDownload: Bool {
        urlValidation.isValid && !downloadState.isActive && !separationState.isActive
    }

    var isYtDlpAvailable: Bool { ytDlpPath != nil }

    // MARK: - Initialization
    init() {
        // Match the manual yt-dlp workflow, which saves into ~/Downloads.
        downloadDirectory = Self.downloadsDirectory
        // Exporting means "put a copy somewhere I choose", so it defaults to
        // Downloads rather than the folder the stems already live in.
        exportDestination = Self.downloadsDirectory

        // WAV stays the default: it is what the mixer reads most cheaply, and
        // compressing by surprise would be a poor default for source separation.
        let storedFormat = UserDefaults.standard.string(forKey: "stemFormat")
        stemFormat = storedFormat.flatMap(AudioFormat.init(rawValue:)) ?? .wav
        let storedBitrate = UserDefaults.standard.integer(forKey: "stemBitrate")
        stemBitrate = AudioBitrate(rawValue: storedBitrate) ?? .default
        setupDefaultOutputDirectory()
        setupDefaultTracks()
        refreshToolStatus()
    }

    /// Re-detect yt-dlp. Cheap enough to call on appearance, and keeps the UI
    /// honest if the user installs or removes the tool while the app is running.
    func refreshToolStatus() {
        let availability = MediaDownloader.checkAvailability()
        ytDlpPath = availability.ytDlp
        ytDlpVersion = availability.ytDlp.flatMap { MediaDownloader.installedVersion(of: $0) }
        ffmpegPath = availability.ffmpeg
        appLog("yt-dlp: \(ytDlpPath?.path ?? "not found") version \(ytDlpVersion ?? "unknown")")
    }

    /// Probe the Python environment for the settings panel.
    ///
    /// Kept separate from `refreshToolStatus` because it spawns interpreters,
    /// so it runs off the main thread and only when the panel is on screen.
    func refreshEnvironmentStatus() {
        guard !isCheckingEnvironment else { return }
        isCheckingEnvironment = true

        Task { @MainActor in
            let scriptURL = SeparationEngine.scriptURL
            let interpreter = await Task.detached {
                PythonLocator.clearCache()
                return PythonLocator.locate(scriptURL: scriptURL)
            }.value

            self.pythonInterpreter = interpreter
            self.isCheckingEnvironment = false
            appLog("python: \(interpreter?.url.path ?? "not found"), missing \(interpreter?.missingModules.joined(separator: ", ") ?? "-")")
        }
    }

    func openSettings() {
        isShowingSettings = true
    }

    // MARK: - Clipboard suggestion

    /// Offer a URL sitting on the clipboard, rather than silently pasting it.
    ///
    /// macOS allows reading the pasteboard without a prompt, so this stays an
    /// explicit suggestion the user accepts: nothing is filled in on their
    /// behalf, and a dismissed value is not offered again.
    func checkClipboardForURL() {
        guard downloadURLString.isEmpty, !downloadState.isActive, !separationState.isActive else {
            clipboardSuggestion = nil
            return
        }

        guard let raw = NSPasteboard.general.string(forType: .string) else {
            clipboardSuggestion = nil
            return
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != dismissedClipboardValue,
              trimmed.count < 2048,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            clipboardSuggestion = nil
            return
        }

        clipboardSuggestion = trimmed
    }

    func acceptClipboardSuggestion() {
        guard let suggestion = clipboardSuggestion else { return }
        downloadURLString = suggestion
        clipboardSuggestion = nil
    }

    func dismissClipboardSuggestion() {
        dismissedClipboardValue = clipboardSuggestion
        clipboardSuggestion = nil
    }

    /// Accept a link dropped onto the zone.
    func acceptDroppedURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        appLog("Accepted dropped link: \(url.absoluteString)")
        downloadURLString = url.absoluteString
        clipboardSuggestion = nil
    }
    
    /// The user's Downloads folder, falling back to ~/Downloads if the system
    /// query fails. Shared by the separation output and the download destination.
    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    private func setupDefaultOutputDirectory() {
        let defaultURL = Self.downloadsDirectory.appendingPathComponent("ariels_splitter_output")
        outputDirectory = defaultURL

        // If the folder cannot be created, leave outputDirectory nil rather than
        // advertising a path we cannot write to: canStartSeparation checks for
        // nil, so this surfaces as a disabled button instead of a run that fails
        // only once Demucs tries to save its stems.
        do {
            try FileManager.default.createDirectory(at: defaultURL, withIntermediateDirectories: true)
        } catch {
            appLog("Could not create default output directory at \(defaultURL.path): \(error.localizedDescription)")
            outputDirectory = nil
        }
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
            guard FileManager.default.fileExists(atPath: url.path) else {
                self.separationState = .failed("File not found: \(url.lastPathComponent)")
                return
            }
            
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
    
    // MARK: - URL Download
    func selectDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where to save downloaded media"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        downloadDirectory = url
    }

    func startDownload() {
        appLog("startDownload() called for kind: \(downloadKind.rawValue)")
        guard canStartDownload, case .valid(let validatedURL) = urlValidation else { return }

        // Use the normalised form so a scheme-less paste like "youtube.com/..."
        // reaches yt-dlp as a proper https URL.
        let urlString = validatedURL.absoluteString
        let kind = downloadKind
        let destination = downloadDirectory

        downloadState = .preparing
        lastDownloadedVideoURL = nil

        Task { @MainActor in
            let downloader = MediaDownloader()
            self.mediaDownloader = downloader

            do {
                let result = try await downloader.download(
                    urlString: urlString,
                    kind: kind,
                    destinationDirectory: destination,
                    progressHandler: { state in
                        Task { @MainActor in
                            // A late progress line must not overwrite a terminal state.
                            if self.downloadState.isActive || self.downloadState == .preparing {
                                self.downloadState = state
                            }
                        }
                    }
                )

                appLog("Download finished. audio: \(result.audio?.path ?? "none"), video: \(result.video?.path ?? "none")")
                self.lastDownloadedVideoURL = result.video
                self.downloadState = .completed(audioURL: result.audio, videoURL: result.video)

                // Hand the audio straight to the existing separation pipeline.
                if let audioURL = result.audio {
                    self.loadAudioFile(url: audioURL)
                }

            } catch DownloadError.cancelled {
                self.downloadState = .cancelled
            } catch let error as DownloadError {
                let failure = error.failure ?? DownloadFailure(message: error.localizedDescription)
                appLog("Download failed: \(failure.message)")
                self.downloadState = .failed(failure)
            } catch {
                self.downloadState = .failed(DownloadFailure(message: error.localizedDescription))
            }

            self.mediaDownloader = nil
        }
    }

    func cancelDownload() {
        mediaDownloader?.cancel()
        downloadState = .cancelled
    }

    func revealDownloadedVideo() {
        guard let url = lastDownloadedVideoURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - yt-dlp Maintenance
    func checkForToolUpdate() {
        guard let ytDlp = ytDlpPath, !updateState.isBusy else { return }
        updateState = .checking

        Task { @MainActor in
            // Network round-trip; keep it off the main thread.
            let check = await Task.detached { ToolUpdater.checkVersion(ytDlp: ytDlp) }.value

            guard let check else {
                self.updateState = .failed("Could not determine the installed yt-dlp version.")
                return
            }
            self.ytDlpVersion = check.current

            guard let latest = check.latest else {
                // No "Latest version:" line means the lookup never completed —
                // usually no network. Saying "up to date" here would be a guess.
                self.updateState = .checkUnavailable(current: check.current)
                return
            }

            if check.isOutdated {
                self.updateState = .updateAvailable(current: check.current, latest: latest)
            } else {
                self.updateState = .upToDate(version: check.current)
            }
        }
    }

    func updateTool() {
        guard let ytDlp = ytDlpPath, !updateState.isBusy else { return }
        let previousVersion = ytDlpVersion ?? "unknown"
        updateState = .updating

        Task { @MainActor in
            let outcome = await Task.detached { ToolUpdater.update(ytDlp: ytDlp) }.value

            switch outcome {
            case .success:
                self.refreshToolStatus()
                let newVersion = self.ytDlpVersion ?? "unknown"
                self.updateState = .updated(from: previousVersion, to: newVersion)
            case .failure(let message):
                self.updateState = .failed(message.isEmpty ? "The update command failed." : message)
            }
        }
    }

    // MARK: - Track Selection

    /// The stem list is an input to a run, so it is frozen once one starts.
    /// The UI hides the selector while separating; this guard means a change can
    /// never land mid-run even if some other path reaches these methods.
    private var canEditTrackSelection: Bool { !separationState.isActive }

    func selectAllTracks() {
        guard canEditTrackSelection else { return }
        for i in stemTracks.indices where stemTracks[i].isAvailable {
            stemTracks[i].isSelected = true
        }
    }

    func deselectAllTracks() {
        guard canEditTrackSelection else { return }
        for i in stemTracks.indices where stemTracks[i].isAvailable {
            stemTracks[i].isSelected = false
        }
    }

    func toggleTrack(_ track: StemTrack) {
        guard canEditTrackSelection, let index = stemTracks.firstIndex(of: track) else { return }
        stemTracks[index].isSelected.toggle()
    }
    
    // MARK: - Separation
    func startSeparation() {
        appLog("startSeparation() called")
        guard let fileInfo = audioFileInfo, let outputDir = outputDirectory else {
            appLog("Cannot start separation: missing fileInfo or outputDir")
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileInfo.url.path) else {
            self.separationState = .failed("Input file not found: \(fileInfo.url.lastPathComponent)")
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
                let producedFiles = try await engine.separate(
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
                
                // separate.py always writes WAV; compress afterwards if the user
                // asked for something smaller.
                let finalFiles = self.stemFormat == .wav
                    ? producedFiles
                    : await self.compressStems(producedFiles)

                // Match on the Demucs source name against the paths the script
                // reported, rather than rebuilding a filename from the display
                // name. The two had drifted: "Piano & Keys".rawValue never
                // matched piano.wav, so that stem was silently missing from the
                // mixer, and the others only matched because macOS filesystems
                // are case-insensitive by default.
                for i in self.stemTracks.indices {
                    let sourceName = self.stemTracks[i].category.demucsSourceName
                    if let fileURL = finalFiles[sourceName],
                       FileManager.default.fileExists(atPath: fileURL.path) {
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
    
    /// Compress the freshly written WAV stems to the configured format.
    ///
    /// A stem that fails to convert keeps its WAV rather than disappearing, so a
    /// codec problem costs disk space instead of the whole run.
    private func compressStems(_ produced: [String: URL]) async -> [String: URL] {
        let format = stemFormat
        let bitrate = stemBitrate.rawValue
        let items = Array(produced)
        var converted = produced

        for (index, item) in items.enumerated() {
            separationState = .separating(
                progress: 0.90 + 0.10 * (Double(index) / Double(max(items.count, 1))),
                currentStem: "Converting \(item.key) to \(format.title)...",
                resources: nil
            )

            // ffmpeg runs synchronously; keep it off the main actor.
            let result = await Task.detached { () -> URL? in
                do {
                    return try AudioTranscoder.convertReplacingOriginal(
                        source: item.value, format: format, bitrateKbps: bitrate
                    )
                } catch {
                    return nil
                }
            }.value

            if let result {
                converted[item.key] = result
            } else {
                appLog("Could not convert \(item.key) to \(format.title); keeping WAV")
            }
        }

        return converted
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

    /// Stems that were actually produced, and so can be exported.
    var exportableTracks: [StemTrack] {
        stemTracks.filter { $0.fileURL != nil }
    }

    var canRunExport: Bool {
        switch exportMode {
        case .mixed: return !exportableTracks.isEmpty
        case .individual: return !exportSelection.isEmpty
        }
    }

    /// Base name for exported files, taken from the source audio so a mix is
    /// identifiable rather than another generic "Mixed Track.wav".
    private var exportBaseName: String {
        guard let info = audioFileInfo else { return "mix" }
        return info.url.deletingPathExtension().lastPathComponent
    }

    func presentExport() {
        exportState = .configuring
        exportSelection = Set(exportableTracks.map(\.id))
        // Default to the format the stems are already in, so the common case is
        // a straight copy with no re-encode.
        exportFormat = stemFormat
        exportBitrate = stemBitrate
        isShowingExport = true
    }

    func closeExport() {
        isShowingExport = false
        exportState = .configuring
    }

    func toggleExportSelection(_ track: StemTrack) {
        if exportSelection.contains(track.id) {
            exportSelection.remove(track.id)
        } else {
            exportSelection.insert(track.id)
        }
    }

    func selectExportDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where to export"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportDestination = url
    }

    func runExport() {
        guard canRunExport, !exportState.isExporting else { return }

        let destination = exportDestination
        let mode = exportMode
        exportState = .exporting(progress: 0, detail: "Preparing...")

        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

                let format = self.exportFormat
                let bitrate = self.exportBitrate.rawValue
                var written = 0

                switch mode {
                case .mixed:
                    guard let engine = self.audioEngine else { throw ExportError.noMixerLoaded }
                    self.exportState = .exporting(progress: 0.2, detail: "Mixing down...")

                    let target = Self.availableURL(
                        in: destination,
                        baseName: "\(self.exportBaseName)_mix",
                        ext: format.fileExtension
                    )

                    if format == .wav {
                        try await engine.exportMix(to: target, tracks: self.stemTracks)
                    } else {
                        // exportMix renders PCM, so compressed targets are
                        // rendered to a temporary WAV and then encoded.
                        let temp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("arielsplitter-mix-\(UUID().uuidString).wav")
                        try await engine.exportMix(to: temp, tracks: self.stemTracks)

                        self.exportState = .exporting(progress: 0.6, detail: "Encoding \(format.title)...")
                        try await Task.detached {
                            try AudioTranscoder.convert(source: temp, destination: target,
                                                        format: format, bitrateKbps: bitrate)
                        }.value
                        try? FileManager.default.removeItem(at: temp)
                    }
                    written = 1

                case .individual:
                    let tracks = self.exportableTracks.filter { self.exportSelection.contains($0.id) }
                    guard !tracks.isEmpty else { throw ExportError.nothingSelected }

                    // The stems on disk are in stemFormat; only that exact match
                    // can be copied. ALAC and AAC share the .m4a extension, so
                    // comparing extensions alone would copy one as the other.
                    let canCopy = format == self.stemFormat

                    for (index, track) in tracks.enumerated() {
                        guard let source = track.fileURL else { continue }
                        self.exportState = .exporting(
                            progress: Double(index) / Double(tracks.count),
                            detail: canCopy
                                ? "Copying \(track.displayName)..."
                                : "Encoding \(track.displayName) as \(format.title)..."
                        )

                        let target = Self.availableURL(
                            in: destination,
                            baseName: source.deletingPathExtension().lastPathComponent,
                            ext: format.fileExtension
                        )

                        if canCopy {
                            // Exporting into the folder the stems already live
                            // in would be a copy onto itself; count it and move on.
                            if source.standardizedFileURL != target.standardizedFileURL {
                                try FileManager.default.copyItem(at: source, to: target)
                            }
                        } else {
                            try await Task.detached {
                                try AudioTranscoder.convert(source: source, destination: target,
                                                            format: format, bitrateKbps: bitrate)
                            }.value
                        }
                        written += 1
                    }
                }

                appLog("Exported \(written) file(s) to \(destination.path)")
                self.exportState = .done(count: written, destination: destination)

            } catch {
                appLog("Export failed: \(error.localizedDescription)")
                self.exportState = .failed(error.localizedDescription)
            }
        }
    }

    /// A path that does not already exist, so an export never destroys a file
    /// the user exported earlier.
    private static func availableURL(in directory: URL, baseName: String, ext: String) -> URL {
        let candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        for suffix in 2...999 {
            let next = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        return candidate
    }

    func openExportDestination() {
        if case .done(_, let destination) = exportState {
            NSWorkspace.shared.open(destination)
        } else {
            NSWorkspace.shared.open(exportDestination)
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