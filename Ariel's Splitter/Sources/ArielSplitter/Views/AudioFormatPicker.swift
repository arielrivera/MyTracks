import SwiftUI

/// Format and bitrate selection, shared by Settings and the export dialog.
struct AudioFormatPicker: View {
    @Binding var format: AudioFormat
    @Binding var bitrate: AudioBitrate

    let title: String
    let help: String

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

            Text(help)
                .font(.system(size: AppStyle.captionFontSize))
                .foregroundColor(.appTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $format) {
                ForEach(AudioFormat.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                Text(format.detail)
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text(format.approximateSizeDescription(bitrateKbps: bitrate.rawValue))
                    .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                    .foregroundColor(.appTextTertiary)
            }
            .fixedSize(horizontal: false, vertical: true)

            // Bitrate only means anything for the lossy formats.
            if format.isLossy {
                HStack(spacing: AppStyle.smallSpacing) {
                    Text("Bitrate")
                        .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                        .foregroundColor(.appTextSecondary)

                    Picker("", selection: $bitrate) {
                        ForEach(AudioBitrate.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.top, 2)
            }
        }
    }
}
