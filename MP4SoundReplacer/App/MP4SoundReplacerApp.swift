import SwiftUI

@main
struct MP4SoundReplacerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
