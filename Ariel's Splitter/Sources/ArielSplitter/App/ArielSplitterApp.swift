import SwiftUI

@main
struct ArielSplitterApp: App {
    @StateObject private var appViewModel = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("File") {
                Button("Open Audio File...") {
                    appViewModel.openFileDialog()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Open Results Folder...") {
                    appViewModel.openResultsFolder()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appViewModel.separationState != .completed)
            }
            CommandMenu("Debug") {
                Button("Run Auto Test") {
                    let testURL = URL(fileURLWithPath: NSHomeDirectory())
                        .appendingPathComponent("Downloads/samplesong.x")
                    appViewModel.loadAudioFile(url: testURL)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        appViewModel.startSeparation()
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }
    }
}
