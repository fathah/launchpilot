import SwiftUI

@main
struct launchpilotApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Project Folder…") {
                    Task { await appState.addProjectFromPicker() }
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
