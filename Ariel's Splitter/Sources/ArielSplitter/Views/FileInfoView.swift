import SwiftUI

struct FileInfoView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: AppStyle.smallSpacing) {
            HStack {
                Label("Audio File", systemImage: "doc.audiovisual")
                    .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Spacer()
            }
            
            if let info = appViewModel.audioFileInfo {
                // Name and path get their own full-width rows and wrap freely.
                // Sharing one row with the metadata badges gave the name a fifth
                // of the width, which truncated all but the shortest filenames.
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    Text(info.url.deletingLastPathComponent().path)
                        .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                        .foregroundColor(colorScheme == .dark ? .appTextTertiary : .appTextSecondaryLight)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AppStyle.spacing) {
                    FileInfoBadge(label: "Format", value: info.format)
                    FileInfoBadge(label: "Duration", value: info.formattedDuration)
                    FileInfoBadge(label: "Sample Rate", value: info.formattedSampleRate)
                    FileInfoBadge(label: "Channels", value: info.formattedChannels)
                }
            }
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
    }
}

struct FileInfoBadge: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
            Text(value)
                .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}