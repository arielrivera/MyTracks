import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme

    /// Shown on launch when setup.sh has not been run, or ffmpeg/Python is
    /// missing. Settings already reports this, but a first-time Mac never
    /// opens Settings looking for an error.
    private var environmentNotice: some View {
        HStack(alignment: .top, spacing: AppStyle.smallSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.appWarning)
            VStack(alignment: .leading, spacing: 4) {
                Text("This Mac is not set up yet")
                    .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Text(appViewModel.environmentStatusSummary)
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("./setup.sh --install-tools")
                    .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                    )
            }
            Spacer()
            Button("Details...") { appViewModel.openSettings() }
                .buttonStyle(.glass(color: .appWarning, compact: true))
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
    }

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

                if !appViewModel.isCheckingEnvironment && !appViewModel.isEnvironmentReady {
                    environmentNotice
                }

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
                    // becomes the mixer. Export lives inside it as a dialog.
                    MixerView()

                    // Fills what was empty space below the mixer, and gives the
                    // written files somewhere to be seen.
                    OutputFilesView()
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
        .sheet(isPresented: $appViewModel.isShowingExport) {
            ExportDialogView()
                .environmentObject(appViewModel)
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