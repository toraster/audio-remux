import Foundation

/// プロジェクトの処理状態
enum ProjectState: Equatable {
    case idle
    case loading
    case ready
    case exporting(progress: Double)
    case completed(outputURL: URL)
    case error(message: String)

    var isProcessing: Bool {
        switch self {
        case .loading, .exporting:
            return true
        default:
            return false
        }
    }
}

/// プロジェクト（音声差し替え作業単位）
struct Project {
    var videoFile: MediaFile?
    var audioFile: MediaFile?
    var exportSettings = ExportSettings()
    var state: ProjectState = .idle

    /// 両方のファイルが設定されているか
    var isReady: Bool {
        videoFile != nil && audioFile != nil
    }

    /// エクスポート可能か
    var canExport: Bool {
        isReady && !state.isProcessing
    }

    /// プロジェクトをリセット
    mutating func reset() {
        videoFile = nil
        audioFile = nil
        exportSettings = ExportSettings()
        state = .idle
    }
}
