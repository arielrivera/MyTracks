import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme

    /// Shown only when the output folder is missing, which silently disables
    /// Start. Without this the button would look broken for no visible reason,
    /// now that the folder is configured in Settings rather than in the flow.
    private var missingOutputFolderNotice: some View {
        HStack(spacing: AppStyle.smallSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.appWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("No output folder set")
                    .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Text("Separated stems need somewhere to go before a run can start.")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextSecondary)
            }
            Spacer()
            Button("Choose in Settings...") { appViewModel.openSettings() }
                .buttonStyle(.glass(color: .appWarning, compact: true))
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
    }

    /// Progress is worth showing while a run is underway, and afterwards only
    /// when it ended badly — on success the mixer replaces it entirely.
    private var showsProgress: Bool {
        switch appViewModel.separationState {
        case .preparing, .downloadingModels, .separating, .cancelled, .failed:
            return true
        case .idle, .completed:
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppStyle.largeSpacing) {
                // Header
                HeaderView()

                if !appViewModel.hasAudioFile {
                    // Single entry point: drop a file, drop a link, paste a URL,
                    // or click to browse.
                    DragDropView()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 320)

                    // Download options stay hidden until there is a link to act
                    // on, so the idle window is just the one zone.
                    if appViewModel.hasPendingDownloadURL {
                        URLDownloadView()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } else if appViewModel.workflowPhase == .finished {
                    // Nothing left to configure — the run is done, so the window
                    // becomes the mixer.
                    MixerView()
                    ExportView()
                } else {
                    FileInfoView()

                    // Stem choice is an input to a run: once one is underway it
                    // cannot take effect, so it is removed rather than left on
                    // screen looking editable. The output folder lives in
                    // Settings, so only the blocking case surfaces here.
                    if appViewModel.workflowPhase == .ready {
                        TrackSelectorView()

                        if appViewModel.outputDirectory == nil {
                            missingOutputFolderNotice
                        }
                    }

                    // Start while ready, Cancel while running.
                    SeparationControlsView()

                    if showsProgress {
                        SeparationProgressView()
                    }
                }
            }
            .padding(AppStyle.standardPadding)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.2), value: appViewModel.hasPendingDownloadURL)
            .animation(.easeOut(duration: 0.2), value: appViewModel.clipboardSuggestion)
            .animation(.easeOut(duration: 0.25), value: appViewModel.workflowPhase)
        }
        .frame(minWidth: 760, idealWidth: 800, maxWidth: .infinity,
               minHeight: 600, idealHeight: 900, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.appBackground : Color.appBackgroundLight)
        .sheet(isPresented: $appViewModel.isShowingSettings) {
            SettingsView()
                .environmentObject(appViewModel)
        }
        .onAppear {
            let triggerURL = URL(fileURLWithPath: "/tmp/ariel_splitter_autotest")
            guard FileManager.default.fileExists(atPath: triggerURL.path) else { return }
            let testURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Downloads/samplesong.x")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                appViewModel.loadAudioFile(url: testURL)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                appViewModel.startSeparation()
            }
        }
    }
}

// The #Preview macro is backed by a plugin that ships with Xcode, not with the
// Command Line Tools, so it cannot be expanded in a SwiftPM build.
#if !SWIFT_PACKAGE
#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .frame(width: 800, height: 900)
}
#endif