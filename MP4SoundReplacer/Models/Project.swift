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

    // 波形データ
    var videoWaveform: WaveformData?
    var audioWaveform: WaveformData?

    // 同期分析
    var syncAnalysisState: SyncAnalysisState = .idle
    var lastSyncResult: SyncAnalysisResult?

    /// 両方のファイルが設定されているか
    var isReady: Bool {
        videoFile != nil && audioFile != nil
    }

    /// エクスポート可能か
    var canExport: Bool {
        isReady && !state.isProcessing
    }

    /// 波形データが両方揃っているか
    var hasWaveforms: Bool {
        videoWaveform != nil && audioWaveform != nil
    }

    /// プロジェクトをリセット
    mutating func reset() {
        videoFile = nil
        audioFile = nil
        exportSettings = ExportSettings()
        state = .idle
        videoWaveform = nil
        audioWaveform = nil
        syncAnalysisState = .idle
        lastSyncResult = nil
    }
}
