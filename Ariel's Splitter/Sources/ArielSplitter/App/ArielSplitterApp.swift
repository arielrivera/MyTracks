import SwiftUI
import AppKit

/// Promotes the process to a regular, activatable app.
///
/// Launched as a bare SwiftPM executable there is no .app bundle, so macOS
/// treats the process as an accessory: the window opens without ever becoming
/// key. A non-key window cannot host a text caret, which is why clicking into a
/// text field did nothing while right-click → Paste still worked — context menus
/// do not require key status. Setting the policy explicitly restores normal
/// focus, keyboard input and menu-bar behaviour whether or not the binary is
/// wrapped in a bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ArielSplitterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
