import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppStyle.largeSpacing) {
                // Header
                HeaderView()
                
                if !appViewModel.hasAudioFile {
                    // Drag & Drop Zone
                    DragDropView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                } else {
                    // File Info
                    FileInfoView()
                    
                    // Track Selector
                    TrackSelectorView()
                    
                    // Output Directory
                    OutputDirectoryView()
                    
                    // Separation Controls
                    SeparationControlsView()
                    
                    // Progress
                    if appViewModel.separationState.isActive || 
                       appViewModel.separationState == .completed ||
                       appViewModel.separationState == .cancelled {
                        SeparationProgressView()
                    }
                    if case .failed = appViewModel.separationState {
                        SeparationProgressView()
                    }
                    
                    // Mixer (after separation)
                    if appViewModel.separationState == .completed {
                        MixerView()
                        
                        // Export Section
                        ExportView()
                    }
                }
            }
            .padding(AppStyle.standardPadding)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 800, maxWidth: .infinity,
               minHeight: 600, idealHeight: 900, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.appBackground : Color.appBackgroundLight)
        .onAppear {
            let triggerURL = URL(fileURLWithPath: "/tmp/ariel_splitter_autotest")
            guard FileManager.default.fileExists(atPath: triggerURL.path) else { return }
            let testURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Downloads/SteveVai-TenderSurrender.mp4")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                appViewModel.loadAudioFile(url: testURL)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                appViewModel.startSeparation()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .frame(width: 800, height: 900)
}