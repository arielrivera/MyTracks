import SwiftUI

struct HeaderView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [Color.appPrimary, Color.appPrimary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Ariel's Splitter")
                    .font(.system(size: AppStyle.titleFontSize, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                
                Text("AI-Powered Music Source Separation")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
            }
            
            Spacer()
            
            if appViewModel.hasAudioFile {
                Button(action: { appViewModel.reset() }) {
                    Label("New Session", systemImage: "plus.square")
                }
                .buttonStyle(.secondary)
            }
        }
    }
}