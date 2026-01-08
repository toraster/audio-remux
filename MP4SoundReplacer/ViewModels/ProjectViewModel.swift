import Foundation
import SwiftUI

/// プロジェクト管理ViewModel
@MainActor
class ProjectViewModel: ObservableObject {
    @Published var project = Project()

    private let ffmpegService = FFmpegService.shared
    private let ffprobeService = FFprobeService.shared

    /// FFmpegが利用可能か
    var isFFmpegAvailable: Bool {
        ffmpegService.isAvailable
    }

    /// 動画ファイルを設定
    func setVideoFile(url: URL) {
        project.state = .loading

        Task {
            do {
                let mediaFile = try await ffprobeService.getMediaInfo(url: url)
                project.videoFile = mediaFile
                updateState()
            } catch {
                project.state = .error(message: error.localizedDescription)
            }
        }
    }

    /// 音声ファイルを設定
    func setAudioFile(url: URL) {
        project.state = .loading

        Task {
            do {
                let mediaFile = try await ffprobeService.getMediaInfo(url: url)
                project.audioFile = mediaFile
                updateState()
            } catch {
                project.state = .error(message: error.localizedDescription)
            }
        }
    }

    /// 動画ファイルをクリア
    func clearVideoFile() {
        project.videoFile = nil
        updateState()
    }

    /// 音声ファイルをクリア
    func clearAudioFile() {
        project.audioFile = nil
        updateState()
    }

    /// プロジェクトをリセット
    func reset() {
        project.reset()
    }

    /// 状態を更新
    private func updateState() {
        if project.isReady {
            project.state = .ready
        } else {
            project.state = .idle
        }
    }

    /// エクスポート実行
    func export() {
        guard let videoFile = project.videoFile,
              let audioFile = project.audioFile else {
            return
        }

        let settings = project.exportSettings
        let outputURL = settings.outputURL(from: videoFile.url)

        project.state = .exporting(progress: 0)

        Task {
            do {
                try await ffmpegService.replaceAudio(
                    videoURL: videoFile.url,
                    audioURL: audioFile.url,
                    outputURL: outputURL,
                    settings: settings
                )

                project.state = .completed(outputURL: outputURL)
            } catch {
                project.state = .error(message: error.localizedDescription)
            }
        }
    }

    /// 出力先を選択
    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            project.exportSettings.outputDirectory = url
        }
    }
}
