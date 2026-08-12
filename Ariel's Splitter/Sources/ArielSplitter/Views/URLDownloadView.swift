import SwiftUI

struct URLDownloadView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var showingToolDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            header

            if appViewModel.isYtDlpAvailable {
                urlField
                kindPicker
                destinationRow
                actionRow
                statusSection
            } else {
                missingToolNotice
            }

            if showingToolDetails {
                toolDetails
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
            Button {
                withAnimation { showingToolDetails.toggle() }
            } label: {
                Image(systemName: showingToolDetails ? "chevron.up.circle" : "gearshape")
                    .foregroundColor(.appTextSecondary)
            }
            .buttonStyle(.plain)
            .help("yt-dlp status and updates")
        }
    }

    // MARK: - Inputs

    private var urlField: some View {
        HStack(spacing: AppStyle.smallSpacing) {
            Image(systemName: "link")
                .foregroundColor(.appAccentSecondary)

            TextField("Paste a video URL", text: $appViewModel.downloadURLString)
                .textFieldStyle(.plain)
                .font(.system(size: AppStyle.bodyFontSize))
                .disabled(appViewModel.downloadState.isActive)
                .onSubmit {
                    if appViewModel.canStartDownload { appViewModel.startDownload() }
                }

            if !appViewModel.downloadURLString.isEmpty && !appViewModel.downloadState.isActive {
                Button {
                    appViewModel.downloadURLString = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.appTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                .stroke(colorScheme == .dark ? Color.appBorder : Color.appBorderLight, lineWidth: 1)
        )
    }

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

    private var destinationRow: some View {
        HStack(spacing: AppStyle.smallSpacing) {
            Image(systemName: "folder.fill")
                .foregroundColor(.appAccentSecondary)
                .font(.system(size: AppStyle.captionFontSize))
            Text(appViewModel.downloadDirectory.path)
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Change") { appViewModel.selectDownloadDirectory() }
                .buttonStyle(.plain)
                .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                .foregroundColor(.appAccent)
                .disabled(appViewModel.downloadState.isActive)
        }
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
                            .buttonStyle(.plain)
                            .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                            .foregroundColor(.appAccent)
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
                        .buttonStyle(.plain)
                        .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                        .foregroundColor(.appAccent)
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

    private var toolDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("yt-dlp")
                    .font(.system(size: AppStyle.captionFontSize, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text(appViewModel.ytDlpVersion ?? "not found")
                    .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                    .foregroundColor(.appTextSecondary)
            }
            if let path = appViewModel.ytDlpPath {
                Text(path.path)
                    .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                    .foregroundColor(.appTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: AppStyle.smallSpacing) {
                Button("Check for updates") { appViewModel.checkForToolUpdate() }
                    .buttonStyle(.secondary)
                    .disabled(!appViewModel.isYtDlpAvailable || appViewModel.updateState.isBusy)

                if case .updateAvailable = appViewModel.updateState {
                    Button("Update now") { appViewModel.updateTool() }
                        .buttonStyle(.glass(color: .appWarning, compact: true))
                }
            }
            updateStatusLine
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
