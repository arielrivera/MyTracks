import SwiftUI

/// Consolidated settings, presented as a sheet from the gear in the header.
///
/// Anything that is configuration rather than part of the per-track workflow
/// belongs here, so the main window stays focused on load → select → separate.
struct SettingsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.largeSpacing) {
                    locationsSection
                    downloaderSection
                    environmentSection
                }
                .padding(AppStyle.standardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(width: 580, height: 620)
        .background(colorScheme == .dark ? Color.appBackground : Color.appBackgroundLight)
        .onAppear {
            appViewModel.refreshToolStatus()
            appViewModel.refreshEnvironmentStatus()
        }
    }

    // MARK: - Chrome

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.appAccent)
            Text("Settings")
                .font(.system(size: AppStyle.titleFontSize, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
            Spacer()
        }
        .padding(.horizontal, AppStyle.standardPadding)
        .padding(.vertical, AppStyle.smallPadding)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.glass())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, AppStyle.standardPadding)
        .padding(.vertical, AppStyle.smallPadding)
    }

    // MARK: - Sections

    private var locationsSection: some View {
        settingsSection("Locations", icon: "folder") {
            VStack(alignment: .leading, spacing: AppStyle.spacing) {
                pathRow(
                    label: "Output folder",
                    help: "Where separated stems are written.",
                    path: appViewModel.outputDirectory?.path ?? "Not set",
                    action: { appViewModel.selectOutputDirectory() },
                    isDisabled: appViewModel.separationState.isActive
                )

                if appViewModel.outputDirectory == nil {
                    Label("Separation cannot start until an output folder is set.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: AppStyle.captionFontSize))
                        .foregroundColor(.appWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                pathRow(
                    label: "Download folder",
                    help: "Where audio and video fetched from a URL are saved.",
                    path: appViewModel.downloadDirectory.path,
                    action: { appViewModel.selectDownloadDirectory() },
                    isDisabled: appViewModel.downloadState.isActive
                )
            }
        }
    }

    private var downloaderSection: some View {
        settingsSection("Downloader", icon: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
                // Attribution — downloads are entirely the work of a separate
                // project, whose update cadence is why this panel exists.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Powered by yt-dlp")
                        .font(.system(size: AppStyle.bodyFontSize, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

                    Text("""
                    URL downloads are handled by yt-dlp, a free and open-source \
                    command-line media downloader supporting thousands of sites. \
                    It is a separate project, installed and updated independently \
                    of this app.
                    """)
                        .font(.system(size: AppStyle.captionFontSize))
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("""
                    Sites change their players often, which breaks extraction \
                    until yt-dlp catches up — so keeping it current is usually \
                    the fix when a download stops working.
                    """)
                        .font(.system(size: AppStyle.captionFontSize))
                        .foregroundColor(.appTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link("github.com/yt-dlp/yt-dlp",
                         destination: URL(string: "https://github.com/yt-dlp/yt-dlp")!)
                        .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                        .cursor(.pointingHand)
                }

                Divider()

                if appViewModel.isYtDlpAvailable {
                    toolStatusRow(
                        name: "yt-dlp",
                        version: appViewModel.ytDlpVersion,
                        path: appViewModel.ytDlpPath?.path
                    )

                    HStack(spacing: AppStyle.smallSpacing) {
                        Button("Check for updates") { appViewModel.checkForToolUpdate() }
                            .buttonStyle(.secondary)
                            .disabled(appViewModel.updateState.isBusy)

                        if case .updateAvailable = appViewModel.updateState {
                            Button("Update now") { appViewModel.updateTool() }
                                .buttonStyle(.glass(color: .appWarning, compact: true))
                        }
                    }

                    updateStatusLine
                } else {
                    missingTool(
                        name: "yt-dlp",
                        detail: "Needed only for URL downloads; everything else works without it.",
                        installCommand: "brew install yt-dlp"
                    )
                }
            }
        }
    }

    private var environmentSection: some View {
        settingsSection("Environment", icon: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
                Text("Read-only. These are detected automatically — the app probes the usual install locations, because a GUI app does not inherit your shell's PATH.")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let ffmpeg = appViewModel.ffmpegPath {
                    toolStatusRow(name: "ffmpeg", version: nil, path: ffmpeg.path)
                } else {
                    missingTool(
                        name: "ffmpeg",
                        detail: "Required. Decodes formats libsndfile cannot read, such as .m4a and .mp4.",
                        installCommand: "brew install ffmpeg"
                    )
                }

                Divider()

                pythonStatus
            }
        }
    }

    @ViewBuilder
    private var pythonStatus: some View {
        if appViewModel.isCheckingEnvironment {
            Label("Checking Python environment...", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
        } else if let interpreter = appViewModel.pythonInterpreter {
            VStack(alignment: .leading, spacing: 4) {
                toolStatusRow(name: "Python", version: nil, path: interpreter.url.path)

                if interpreter.isComplete {
                    Label("All separation modules present", systemImage: "checkmark.circle")
                        .font(.system(size: AppStyle.captionFontSize))
                        .foregroundColor(.appSuccess)
                } else {
                    Label("Missing: \(interpreter.missingModules.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                        .foregroundColor(.appWarning)
                    Text("Run ./setup.sh, or install into that interpreter directly.")
                        .font(.system(size: AppStyle.captionFontSize))
                        .foregroundColor(.appTextSecondary)
                }

                Button("Re-check") { appViewModel.refreshEnvironmentStatus() }
                    .buttonStyle(.link())
                    .font(.system(size: AppStyle.captionFontSize, weight: .medium))
            }
        } else {
            missingTool(
                name: "Python",
                detail: "No interpreter with the required modules was found.",
                installCommand: "./setup.sh"
            )
        }
    }

    // MARK: - Building blocks

    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            Label(title, systemImage: icon)
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

            content()
                .padding(AppStyle.smallPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
        }
    }

    private func pathRow(
        label: String,
        help: String,
        path: String,
        action: @escaping () -> Void,
        isDisabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
            Text(help)
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextTertiary)

            HStack {
                Text(path)
                    .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                            .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                    )

                Button("Change...", action: action)
                    .buttonStyle(.glass(color: .appAccentSecondary, compact: true))
                    .disabled(isDisabled)
            }
        }
    }

    private func toolStatusRow(name: String, version: String?, path: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
            if let version {
                Text(version)
                    .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                    .foregroundColor(.appTextSecondary)
            }
            Spacer()
            if let path {
                Text(path)
                    .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                    .foregroundColor(.appTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
            }
        }
    }

    private func missingTool(name: String, detail: String, installCommand: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(name) not found", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                .foregroundColor(.appWarning)
            Text(detail)
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(installCommand)
                .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                )
            Button("Re-check") { appViewModel.refreshToolStatus() }
                .buttonStyle(.link())
                .font(.system(size: AppStyle.captionFontSize, weight: .medium))
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
            Label(from == to ? "Already at \(to)" : "Updated \(from) → \(to)",
                  systemImage: "checkmark.circle.fill")
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
