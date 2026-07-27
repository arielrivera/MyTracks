import SwiftUI

struct OutputDirectoryView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: AppStyle.smallSpacing) {
            HStack {
                Label("Output Location", systemImage: "folder")
                    .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Spacer()
            }
            
            HStack {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.appAccentSecondary)
                    Text(appViewModel.outputDirectory?.path ?? "No folder selected")
                        .font(.system(size: AppStyle.bodyFontSize))
                        .foregroundColor(appViewModel.outputDirectory != nil ? (colorScheme == .dark ? .appText : .appTextLight) : (colorScheme == .dark ? .appTextTertiary : .appTextSecondaryLight))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                        .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                        .stroke(colorScheme == .dark ? Color.appBorder : Color.appBorderLight, lineWidth: 1)
                )
                
                Button(action: { appViewModel.selectOutputDirectory() }) {
                    Text(appViewModel.outputDirectory == nil ? "Choose..." : "Change")
                }
                .buttonStyle(.glass(color: .appAccentSecondary))
            }
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
    }
}