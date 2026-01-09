import SwiftUI

@main
struct MP4SoundReplacerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isFFmpegAvailable = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isFFmpegAvailable {
                    ContentView()
                } else {
                    FFmpegSetupView(isFFmpegAvailable: $isFFmpegAvailable)
                }
            }
            .onAppear {
                checkFFmpegAvailability()
            }
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }

    private func checkFFmpegAvailability() {
        let ffmpegPath = FFmpegDownloadService.shared.ffmpegPath
        let ffprobePath = FFmpegDownloadService.shared.ffprobePath
        let fm = FileManager.default

        // isExecutableFileはquarantine属性があるとfalseを返すため、fileExistsを使用
        let downloadedAvailable = fm.fileExists(atPath: ffmpegPath.path) &&
                                  fm.fileExists(atPath: ffprobePath.path)

        isFFmpegAvailable = downloadedAvailable || FFmpegService.shared.isAvailable
    }
}
