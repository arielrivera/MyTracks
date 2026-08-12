import SwiftUI

/// Download options for a link that has already been entered.
///
/// The URL field itself lives in the drop zone, which is the single entry point
/// for getting media in; this panel only appears once there is something to act
/// on, so the idle window stays uncluttered.
struct URLDownloadView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            header

            if appViewModel.isYtDlpAvailable {
                kindPicker
                actionRow
                statusSection
            } else {
                missingToolNotice
            }
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
        .onAppear { appViewModel.refreshToolStatus() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Download from URL", systemImage: "arrow.down.circle")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
            Spacer()
            // Destination shown read-only; it is changed in Settings, which also
            // holds the yt-dlp status and update controls that used to live here.
            Button {
                appViewModel.openSettings()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: AppStyle.captionFontSize))
                    Text(appViewModel.downloadDirectory.lastPathComponent)
                        .font(.system(size: AppStyle.captionFontSize))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.link(color: .appTextSecondary))
            .help("Saving to \(appViewModel.downloadDirectory.path) — change in Settings")
        }
    }

    // MARK: - Inputs

    private var kindPicker: some View {
        Picker("", selection: $appViewModel.downloadKind) {
            ForEach(DownloadKind.allCases) { kind in
                Label(kind.title, systemImage: kind.iconName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(appViewModel.downloadState.isActive)
    }

    private var actionRow: some View {
        HStack(spacing: AppStyle.smallSpacing) {
            if appViewModel.downloadState.isActive {
                Button("Cancel") { appViewModel.cancelDownload() }
                    .buttonStyle(.secondary)
            } else {
                Button {
                    appViewModel.startDownload()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.glass())
                .disabled(!appViewModel.canStartDownload)
                .opacity(appViewModel.canStartDownload ? 1 : 0.5)
            }

            Spacer()

            if appViewModel.downloadKind.producesAudio {
                Text("Loads for separation when finished")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextTertiary)
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        switch appViewModel.downloadState {
        case .idle:
            EmptyView()

        case .preparing, .downloading, .postProcessing:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: appViewModel.downloadState.progressValue)
                    .progressViewStyle(.linear)
                Text(appViewModel.downloadState.statusText)
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextSecondary)
            }

        case .completed(let audioURL, let videoURL):
            VStack(alignment: .leading, spacing: 4) {
                Label("Download complete", systemImage: "checkmark.circle.fill")
                    .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                    .foregroundColor(.appSuccess)
                if let audioURL {
                    Text(audioURL.lastPathComponent)
                        .font(.system(size: AppStyle.captionFontSize))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let videoURL {
                    HStack(spacing: 6) {
                        Text(videoURL.lastPathComponent)
                            .font(.system(size: AppStyle.captionFontSize))
                            .foregroundColor(.appTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Show in Finder") { appViewModel.revealDownloadedVideo() }
                            .buttonStyle(.link())
                            .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                    }
                }
            }

        case .cancelled:
            Text("Cancelled")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)

        case .failed(let failure):
            failureView(failure)
        }
    }

    private func failureView(_ failure: DownloadFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                .foregroundColor(.appWarning)
                .fixedSize(horizontal: false, vertical: true)

            // Extraction breaks when a site changes its player, and the fix is
            // nearly always a newer yt-dlp — so offer it right where it failed.
            if failure.looksLikeOutdatedTool {
                Text("This usually means yt-dlp needs updating — sites change and break it regularly.")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppStyle.smallSpacing) {
                    Button("Update yt-dlp") { appViewModel.updateTool() }
                        .buttonStyle(.glass(color: .appWarning, compact: true))
                        .disabled(appViewModel.updateState.isBusy)
                    Button("Retry") { appViewModel.startDownload() }
                        .buttonStyle(.link())
                        .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                }
                updateStatusLine
            } else if !failure.details.isEmpty {
                DisclosureGroup("Details") {
                    ScrollView {
                        Text(failure.details)
                            .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                            .foregroundColor(.appTextSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
                .font(.system(size: AppStyle.captionFontSize))
            }
        }
    }

    // MARK: - Tool status

    private var missingToolNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("yt-dlp not found", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                .foregroundColor(.appWarning)
            Text("URL downloads need yt-dlp. Install it, then press Re-check.")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
            Text("brew install yt-dlp")
                .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                .foregroundColor(.appText)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                )
            Button("Re-check") { appViewModel.refreshToolStatus() }
                .buttonStyle(.secondary)
        }
    }

    @ViewBuilder
    private var updateStatusLine: some View {
        switch appViewModel.updateState {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking...", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
        case .upToDate(let version):
            Label("Up to date (\(version))", systemImage: "checkmark.circle")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appSuccess)
        case .checkUnavailable(let current):
            VStack(alignment: .leading, spacing: 2) {
                Label("Couldn't check for updates", systemImage: "wifi.slash")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appWarning)
                Text("Installed: \(current). The latest version could not be looked up — check your connection.")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .updateAvailable(let current, let latest):
            Label("Update available: \(current) → \(latest)", systemImage: "arrow.up.circle")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appWarning)
        case .updating:
            Label("Updating — this can take a minute...", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
        case .updated(let from, let to):
            Label(from == to ? "Already at \(to)" : "Updated \(from) → \(to)", systemImage: "checkmark.circle.fill")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appSuccess)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 2) {
                Label("Update failed", systemImage: "exclamationmark.triangle")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appWarning)
                if let path = appViewModel.ytDlpPath {
                    Text("Run this yourself: \(ToolUpdater.updateCommand(for: path))")
                        .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                        .foregroundColor(.appTextSecondary)
                        .textSelection(.enabled)
                }
                Text(message)
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextTertiary)
                    .lineLimit(3)
            }
        }
    }
}
