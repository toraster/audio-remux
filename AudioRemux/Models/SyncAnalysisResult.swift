import Foundation

/// 同期分析の結果
struct SyncAnalysisResult {
    /// 検出されたオフセット（秒）
    /// 正の値: 置換音声を遅らせる
    /// 負の値: 置換音声の先頭をカット
    let detectedOffset: TimeInterval

    /// 相関係数（0.0 〜 1.0）
    /// 高いほど信頼性が高い
    let confidence: Double

    /// 分析に使用した区間（秒）
    let analyzedRange: ClosedRange<TimeInterval>

    /// 信頼性の評価
    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.8...:
            return .high
        case 0.5..<0.8:
            return .medium
        default:
            return .low
        }
    }

    /// 信頼性レベル
    enum ConfidenceLevel {
        case high
        case medium
        case low

        var description: String {
            switch self {
            case .high:
                return "高い信頼性"
            case .medium:
                return "中程度の信頼性"
            case .low:
                return "低い信頼性（手動調整を推奨）"
            }
        }

        var isReliable: Bool {
            self != .low
        }
    }
}

/// 同期分析の状態
enum SyncAnalysisState: Equatable {
    case idle
    case extractingAudio
    case generatingWaveform
    case analyzing
    case completed(SyncAnalysisResult)
    case error(String)

    var isProcessing: Bool {
        switch self {
        case .extractingAudio, .generatingWaveform, .analyzing:
            return true
        default:
            return false
        }
    }

    var statusMessage: String {
        switch self {
        case .idle:
            return "待機中"
        case .extractingAudio:
            return "音声を抽出中..."
        case .generatingWaveform:
            return "波形を生成中..."
        case .analyzing:
            return "同期分析中..."
        case .completed(let result):
            return "完了: オフセット \(String(format: "%.3f", result.detectedOffset))秒"
        case .error(let message):
            return "エラー: \(message)"
        }
    }

    static func == (lhs: SyncAnalysisState, rhs: SyncAnalysisState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.extractingAudio, .extractingAudio),
             (.generatingWaveform, .generatingWaveform),
             (.analyzing, .analyzing):
            return true
        case (.completed(let l), .completed(let r)):
            return l.detectedOffset == r.detectedOffset && l.confidence == r.confidence
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}
