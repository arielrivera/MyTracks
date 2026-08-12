import SwiftUI

/// Export flow, presented as a sheet from the mixer.
///
/// One dialog covers the whole job: choose what to write, where it goes, then a
/// confirmation with a way straight to the files — rather than a save panel per
/// stem.
struct ExportDialogView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.spacing) {
                    switch appViewModel.exportState {
                    case .configuring:
                        modeChooser
                        if appViewModel.exportMode == .individual {
                            stemChooser
                        }
                        destinationRow
                    case .exporting(let progress, let detail):
                        progressBody(progress: progress, detail: detail)
                    case .done(let count, let destination):
                        doneBody(count: count, destination: destination)
                    case .failed(let message):
                        failureBody(message)
                    }
                }
                .padding(AppStyle.standardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(width: 520, height: 560)
        .background(colorScheme == .dark ? Color.appBackground : Color.appBackgroundLight)
    }

    // MARK: - Chrome

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.appAccent)
            Text("Export")
                .font(.system(size: AppStyle.titleFontSize, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
            Spacer()
        }
        .padding(.horizontal, AppStyle.standardPadding)
        .padding(.vertical, AppStyle.smallPadding)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: AppStyle.smallSpacing) {
            Spacer()

            switch appViewModel.exportState {
            case .configuring:
                Button("Cancel") { appViewModel.closeExport() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                Button("Export") { appViewModel.runExport() }
                    .buttonStyle(.glass())
                    .disabled(!appViewModel.canRunExport)
                    .opacity(appViewModel.canRunExport ? 1 : 0.5)
                    .keyboardShortcut(.defaultAction)

            case .exporting:
                Button("Cancel") { }
                    .buttonStyle(.secondary)
                    .disabled(true)
                    .opacity(0.5)

            case .done:
                Button("Open Results Folder") { appViewModel.openExportDestination() }
                    .buttonStyle(.secondary)

                Button("OK") { appViewModel.closeExport() }
                    .buttonStyle(.glass())
                    .keyboardShortcut(.defaultAction)

            case .failed:
                Button("Close") { appViewModel.closeExport() }
                    .buttonStyle(.secondary)

                Button("Try Again") { appViewModel.exportState = .configuring }
                    .buttonStyle(.glass())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, AppStyle.standardPadding)
        .padding(.vertical, AppStyle.smallPadding)
    }

    // MARK: - Configuring

    private var modeChooser: some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            Text("What would you like to export?")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

            ForEach(ExportMode.allCases) { mode in
                Button {
                    appViewModel.exportMode = mode
                } label: {
                    HStack(alignment: .top, spacing: AppStyle.smallSpacing) {
                        Image(systemName: appViewModel.exportMode == mode
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(appViewModel.exportMode == mode ? .appAccent : .appTextTertiary)

                        VStack(alignment: .leading, spacing: 2) {
                            Label(mode.title, systemImage: mode.iconName)
                                .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                            Text(mode.detail)
                                .font(.system(size: AppStyle.captionFontSize))
                                .foregroundColor(.appTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(AppStyle.smallPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                            .fill(appViewModel.exportMode == mode
                                  ? Color.appAccent.opacity(0.08)
                                  : (colorScheme == .dark ? Color.appSurfaceLight.opacity(0.4)
                                                          : Color.appSurfaceLightLight.opacity(0.4)))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stemChooser: some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            HStack {
                Text("Stems")
                    .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Spacer()
                Button("All") {
                    appViewModel.exportSelection = Set(appViewModel.exportableTracks.map(\.id))
                }
                .buttonStyle(.link())
                .font(.system(size: AppStyle.captionFontSize, weight: .medium))

                Button("None") { appViewModel.exportSelection = [] }
                    .buttonStyle(.link())
                    .font(.system(size: AppStyle.captionFontSize, weight: .medium))
            }

            VStack(spacing: 2) {
                ForEach(appViewModel.exportableTracks) { track in
                    Button {
                        appViewModel.toggleExportSelection(track)
                    } label: {
                        HStack(spacing: AppStyle.smallSpacing) {
                            Image(systemName: appViewModel.exportSelection.contains(track.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(appViewModel.exportSelection.contains(track.id)
                                                 ? .appAccent : .appTextTertiary)

                            Image(systemName: track.category.iconName)
                                .font(.system(size: 12))
                                .foregroundColor(.appTextSecondary)

                            Text(track.displayName)
                                .font(.system(size: AppStyle.bodyFontSize))
                                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

                            Spacer()

                            if let name = track.fileURL?.lastPathComponent {
                                Text(name)
                                    .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                                    .foregroundColor(.appTextTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(padding: 0)
                }
            }
            .padding(.vertical, 4)
            .surfaceCard()

            if appViewModel.exportSelection.isEmpty {
                Text("Select at least one stem.")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appWarning)
            }
        }
    }

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Destination")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

            HStack {
                Text(appViewModel.exportDestination.path)
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

                Button("Change...") { appViewModel.selectExportDestination() }
                    .buttonStyle(.glass(color: .appAccentSecondary, compact: true))
            }

            Text("Existing files are never overwritten — a numbered copy is written instead.")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Running and results

    private func progressBody(progress: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            Text("Exporting...")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(detail)
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func doneBody(count: Int, destination: URL) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            Label("Export complete", systemImage: "checkmark.circle.fill")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(.appSuccess)

            Text(count == 1 ? "1 file written to:" : "\(count) files written to:")
                .font(.system(size: AppStyle.bodyFontSize))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

            Text(destination.path)
                .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                .foregroundColor(.appTextSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureBody(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            Label("Export failed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(.appWarning)
            Text(message)
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
