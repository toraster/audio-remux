import Foundation
import SwiftUI

/// プロジェクト管理ViewModel
@MainActor
class ProjectViewModel: ObservableObject {
    @Published var project = Project()

    private let ffmpegService = FFmpegService.shared
    private let ffprobeService = FFprobeService.shared

    /// 動画ファイル読み込みタスク
    private var videoLoadingTask: Task<Void, Never>?
    /// 音声ファイル読み込みタスク
    private var audioLoadingTask: Task<Void, Never>?
    /// エクスポートタスク
    private var exportTask: Task<Void, Never>?

    /// FFmpegが利用可能か
    var isFFmpegAvailable: Bool {
        // ダウンロード済みFFmpegを直接チェック（fileExistsを使用）
        let ffmpegPath = FFmpegDownloadService.shared.ffmpegPath
        let ffprobePath = FFmpegDownloadService.shared.ffprobePath
        let fm = FileManager.default

        // isExecutableFileはquarantine属性があるとfalseを返すため、fileExistsを使用
        let downloadedAvailable = fm.fileExists(atPath: ffmpegPath.path) &&
                                  fm.fileExists(atPath: ffprobePath.path)

        return downloadedAvailable || ffmpegService.isAvailable
    }

    /// 動画ファイルを設定
    func setVideoFile(url: URL) {
        // 前のタスクをキャンセル
        videoLoadingTask?.cancel()

        project.state = .loading

        videoLoadingTask = Task {
            do {
                let mediaFile = try await ffprobeService.getMediaInfo(url: url)
                // タスクがキャンセルされていないかチェック
                guard !Task.isCancelled else { return }
                project.videoFile = mediaFile
                updateState()
            } catch {
                // タスクがキャンセルされていないかチェック
                guard !Task.isCancelled else { return }
                project.state = .error(message: error.localizedDescription)
            }
        }
    }

    /// 音声ファイルを設定
    func setAudioFile(url: URL) {
        // 前のタスクをキャンセル
        audioLoadingTask?.cancel()

        project.state = .loading

        audioLoadingTask = Task {
            do {
                let mediaFile = try await ffprobeService.getMediaInfo(url: url)
                // タスクがキャンセルされていないかチェック
                guard !Task.isCancelled else { return }
                project.audioFile = mediaFile
                updateState()
            } catch {
                // タスクがキャンセルされていないかチェック
                guard !Task.isCancelled else { return }
                project.state = .error(message: error.localizedDescription)
            }
        }
    }

    /// 動画ファイルをクリア
    func clearVideoFile() {
        // 進行中のタスクをキャンセル
        videoLoadingTask?.cancel()
        videoLoadingTask = nil

        project.videoFile = nil
        updateState()
    }

    /// 音声ファイルをクリア
    func clearAudioFile() {
        // 進行中のタスクをキャンセル
        audioLoadingTask?.cancel()
        audioLoadingTask = nil

        project.audioFile = nil
        updateState()
    }

    /// プロジェクトをリセット
    func reset() {
        // 進行中のタスクをすべてキャンセル
        videoLoadingTask?.cancel()
        videoLoadingTask = nil
        audioLoadingTask?.cancel()
        audioLoadingTask = nil
        exportTask?.cancel()
        exportTask = nil

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

        // 前のエクスポートをキャンセル
        exportTask?.cancel()

        let settings = project.exportSettings
        let outputURL = settings.outputURL(from: videoFile.url)

        project.state = .exporting(progress: 0)

        exportTask = Task {
            do {
                try await ffmpegService.replaceAudio(
                    videoURL: videoFile.url,
                    audioURL: audioFile.url,
                    outputURL: outputURL,
                    settings: settings
                )

                guard !Task.isCancelled else { return }
                project.state = .completed(outputURL: outputURL)
            } catch is CancellationError {
                project.state = .idle
            } catch {
                guard !Task.isCancelled else { return }
                project.state = .error(message: error.localizedDescription)
            }
        }
    }

    /// エクスポートをキャンセル
    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        project.state = .idle
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
