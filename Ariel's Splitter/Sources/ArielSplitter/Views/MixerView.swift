import SwiftUI

struct MixerView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: AppStyle.smallSpacing) {
            HStack {
                Label("Mixer", systemImage: "slider.vertical.3")
                    .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Spacer()
            }
            
            // Playback controls
            HStack(spacing: AppStyle.spacing) {
                Button(action: { appViewModel.togglePlayback() }) {
                    Image(systemName: appViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.appAccent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                
                // Time display
                Text(formatTime(appViewModel.currentTime))
                    .font(.system(size: AppStyle.bodyFontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                    .frame(width: 60)
                
                // Seek bar
                let seekProgress = appViewModel.duration > 0 ? appViewModel.currentTime / appViewModel.duration : 0
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appAccent)
                            .frame(width: geometry.size.width * CGFloat(seekProgress), height: 6)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = max(0, min(1, value.location.x / geometry.size.width))
                                appViewModel.seek(to: ratio * appViewModel.duration)
                            }
                    )
                }
                .frame(height: 6)
                
                Text(formatTime(appViewModel.duration))
                    .font(.system(size: AppStyle.bodyFontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
                    .frame(width: 60)
            }
            
            // Track mixer rows
            ForEach(appViewModel.stemTracks.filter { $0.fileURL != nil }) { track in
                MixerRow(track: track)
            }
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

struct MixerRow: View {
    let track: StemTrack
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            // Track name
            Image(systemName: track.category.iconName)
                .font(.system(size: 12))
                .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
                .frame(width: 16)
            
            Text(track.displayName)
                .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                .frame(width: 120, alignment: .leading)
            
            // Mute button
            Button(action: { appViewModel.toggleMute(for: track) }) {
                Text("M")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(track.isMuted ? .white : (colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(track.isMuted ? Color.appAccent : (colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight))
                    )
            }
            .buttonStyle(.plain)
            
            // Solo button
            Button(action: { appViewModel.toggleSolo(for: track) }) {
                Text("S")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(track.isSolo ? .white : (colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(track.isSolo ? Color.appAccentSecondary : (colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight))
                    )
            }
            .buttonStyle(.plain)
            
            // Volume slider
            Slider(value: Binding(
                get: { track.volume },
                set: { appViewModel.setVolume(for: track, volume: $0) }
            ), in: 0...1)
            .controlSize(.small)
            
            // Volume label
            Text("\(Int(track.volume * 100))%")
                .font(.system(size: AppStyle.captionFontSize, design: .monospaced))
                .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
                .frame(width: 36)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                .fill(track.isMuted ? Color.appAccent.opacity(0.05) : Color.clear)
        )
    }
}