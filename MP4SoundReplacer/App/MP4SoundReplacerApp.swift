import SwiftUI

@main
struct MP4SoundReplacerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var ffmpegChecker = FFmpegAvailabilityChecker()

    var body: some Scene {
        WindowGroup {
            Group {
                if ffmpegChecker.isAvailable {
                    ContentView()
                } else {
                    FFmpegSetupView(onComplete: {
                        ffmpegChecker.recheck()
                    })
                }
            }
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

/// FFmpeg利用可能状態を管理するクラス
@MainActor
class FFmpegAvailabilityChecker: ObservableObject {
    @Published var isAvailable = false

    init() {
        recheck()
    }

    func recheck() {
        isAvailable = FFmpegService.shared.isAvailable
    }
}
