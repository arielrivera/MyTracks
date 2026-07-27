import SwiftUI

struct ExportView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: AppStyle.smallSpacing) {
            HStack {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Spacer()
            }
            
            VStack(spacing: 8) {
                // Individual stem export
                ForEach(appViewModel.stemTracks.filter { $0.fileURL != nil }) { track in
                    HStack {
                        Image(systemName: track.category.iconName)
                            .font(.system(size: 12))
                            .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
                        
                        Text(track.displayName)
                            .font(.system(size: AppStyle.bodyFontSize))
                            .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                        
                        Spacer()
                        
                        Button("Export") {
                            appViewModel.exportStem(track)
                        }
                        .buttonStyle(.glass(color: .appAccentSecondary, compact: true))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                
                Divider()
                    .background(colorScheme == .dark ? Color.appDivider : Color.appDividerLight)
                
                // Mixed export
                HStack {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
                    
                    Text("Mixed Track (current mix)")
                        .font(.system(size: AppStyle.bodyFontSize))
                        .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                    
                    Spacer()
                    
                    Button("Export Mix") {
                        appViewModel.exportMixedTrack()
                    }
                    .buttonStyle(.glass(color: .appAccent))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                
                // Open results folder
                HStack {
                    Spacer()
                    Button(action: { appViewModel.openResultsFolder() }) {
                        Label("Open Results Folder", systemImage: "folder")
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
    }
}