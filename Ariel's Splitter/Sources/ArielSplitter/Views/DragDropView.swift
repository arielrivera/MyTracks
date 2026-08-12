import SwiftUI
import UniformTypeIdentifiers

struct DragDropView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isDragging = false
    @State private var isHovering = false

    /// Highlighted while dragging a file over the zone, and — more subtly — on
    /// hover, since the zone is also a click target ("or click to browse") and
    /// previously gave no indication of that until clicked.
    private var isHighlighted: Bool { isDragging || isHovering }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppStyle.largeCornerRadius)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .fill(isHighlighted ? Color.appAccent : (colorScheme == .dark ? Color.appBorder : Color.appBorderLight))

            RoundedRectangle(cornerRadius: AppStyle.largeCornerRadius)
                .fill(isDragging ? Color.appAccent.opacity(0.05)
                                 : (isHovering ? Color.appAccent.opacity(0.02) : Color.clear))
            
            VStack(spacing: AppStyle.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(
                            colors: [Color.appPrimary, Color.appPrimary.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Drop an audio file here")
                    .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                
                Text("or click to browse")
                    .font(.system(size: AppStyle.bodyFontSize))
                    .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
                
                HStack(spacing: 12) {
                    ForEach(["WAV", "MP3", "M4A", "AIFF", "FLAC"], id: \.self) { format in
                        Text(format)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .appTextTertiary : .appTextSecondaryLight)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                            )
                    }
                }
            }
            .padding(AppStyle.largeSpacing)
        }
        .onDrop(of: [.audio, .fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
            return true
        }
        .contentShape(RoundedRectangle(cornerRadius: AppStyle.largeCornerRadius))
        .onTapGesture {
            appViewModel.openFileDialog()
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .padding(.horizontal, 2)
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.audio.identifier, options: nil) { item, error in
                let url = self.extractURL(from: item)
                DispatchQueue.main.async {
                    if let url = url {
                        self.appViewModel.loadAudioFile(url: url)
                    }
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                let url = self.extractURL(from: item)
                DispatchQueue.main.async {
                    if let url = url {
                        self.appViewModel.loadAudioFile(url: url)
                    }
                }
            }
        }
    }
    
    private func extractURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        } else if let url = item as? URL {
            return url
        }
        return nil
    }
}