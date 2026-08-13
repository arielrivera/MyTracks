import SwiftUI

/// Finder-style listing of the output folder, shown under the mixer once a run
/// has finished — where the window would otherwise be empty.
struct OutputFilesView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var selection: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.smallSpacing) {
            header

            if appViewModel.outputFiles.isEmpty {
                emptyState
            } else {
                columnHeadings
                fileList
                footer
            }
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
        .onAppear { appViewModel.refreshOutputFiles() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Output Files", systemImage: "folder")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

            Spacer()

            Button {
                appViewModel.refreshOutputFiles()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                    .foregroundColor(.appTextSecondary)
            }
            .buttonStyle(.plain)
            .hoverHighlight(padding: 4)
            .help("Refresh")

            Button("Open in Finder") { appViewModel.openResultsFolder() }
                .buttonStyle(.link())
                .font(.system(size: AppStyle.captionFontSize, weight: .medium))
        }
    }

    private var columnHeadings: some View {
        HStack(spacing: AppStyle.smallSpacing) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: 70, alignment: .trailing)
            Text("Modified")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: AppStyle.captionFontSize, weight: .medium))
        .foregroundColor(.appTextTertiary)
        .padding(.horizontal, 8)
    }

    // MARK: - List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(appViewModel.outputFiles) { file in
                    row(for: file)
                }
            }
        }
        // Bounded so a folder with many runs in it does not push the window to
        // an unusable height.
        .frame(maxHeight: 220)
    }

    private func row(for file: OutputFile) -> some View {
        let isSelected = selection == file.url

        return HStack(spacing: AppStyle.smallSpacing) {
            Image(systemName: file.iconName)
                .font(.system(size: 13))
                .foregroundColor(file.isFromCurrentRun ? .appAccent : .appTextTertiary)
                .frame(width: 18)

            Text(file.name)
                .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if file.isFromCurrentRun {
                Text("this run")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.appAccent.opacity(0.12))
                    )
            }

            Text(file.formattedSize)
                .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                .foregroundColor(.appTextSecondary)
                .frame(width: 70, alignment: .trailing)

            Text(file.formattedModified)
                .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                .foregroundColor(.appTextTertiary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.appAccent.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = file.url }
        // Finder's own gesture: double-click opens, which is what people try first.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { appViewModel.open(file) }
        )
        .contextMenu {
            Button("Open") { appViewModel.open(file) }
            Button("Reveal in Finder") { appViewModel.revealInFinder(file) }
        }
        .help(file.url.path)
    }

    private var footer: some View {
        HStack {
            Text(summary)
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextTertiary)
            Spacer()
            if let selection, let file = appViewModel.outputFiles.first(where: { $0.url == selection }) {
                Button("Reveal in Finder") { appViewModel.revealInFinder(file) }
                    .buttonStyle(.link())
                    .font(.system(size: AppStyle.captionFontSize, weight: .medium))
            }
        }
    }

    private var summary: String {
        let files = appViewModel.outputFiles
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let count = files.count == 1 ? "1 file" : "\(files.count) files"
        return "\(count), \(formatter.string(fromByteCount: total))"
    }

    private var emptyState: some View {
        HStack(spacing: AppStyle.smallSpacing) {
            Image(systemName: "tray")
                .foregroundColor(.appTextTertiary)
            Text("No audio files in the output folder yet.")
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextSecondary)
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
