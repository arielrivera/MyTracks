import SwiftUI

struct TrackSelectorView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: AppStyle.smallSpacing) {
            HStack {
                Label("Tracks to Separate", systemImage: "square.grid.2x2")
                    .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Spacer()
                
                HStack(spacing: 8) {
                    Button("All") { appViewModel.selectAllTracks() }
                        .buttonStyle(.glass(color: .appAccentSecondary, compact: true))
                    Button("None") { appViewModel.deselectAllTracks() }
                        .buttonStyle(.glass(color: .appTextSecondary, compact: true))
                }
            }
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 8)
            ], spacing: 8) {
                ForEach(appViewModel.stemTracks) { track in
                    TrackCell(track: track)
                }
            }
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
    }
}

struct TrackCell: View {
    let track: StemTrack
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button(action: { appViewModel.toggleTrack(track) }) {
                Image(systemName: track.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(track.isSelected ? Color.appAccent : (colorScheme == .dark ? Color.appTextTertiary : Color.appBorderLight))
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 11, padding: 2)
            .disabled(!track.isAvailable)
            
            // Icon
            Image(systemName: track.category.iconName)
                .font(.system(size: 14))
                .foregroundColor(track.isAvailable ? (colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight) : .gray)
                .frame(width: 20)
            
            // Name
            Text(track.displayName)
                .font(.system(size: AppStyle.bodyFontSize))
                .foregroundColor(track.isAvailable ? (colorScheme == .dark ? .appText : .appTextLight) : .gray)
            
            Spacer()
            
            // Unavailable indicator
            if !track.isAvailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.appWarning)
                    .help(track.unavailabilityReason ?? "Not available")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                .fill(track.isSelected ? Color.appAccent.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                .stroke(track.isSelected ? Color.appAccent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .opacity(track.isAvailable ? 1.0 : 0.5)
    }
}