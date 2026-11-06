import SwiftUI

@main
struct LingoLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(environment)
        } label: {
            Label("LingoLens", systemImage: "character.bubble")
        }
        .menuBarExtraStyle(.window)

        Window("LingoLens", id: "main") {
            MainWindowView()
                .environmentObject(environment)
        }
        .defaultSize(width: 940, height: 660)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
