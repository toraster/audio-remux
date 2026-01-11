import Foundation

/// 音声コーデックの選択肢
enum AudioCodec: String, CaseIterable, Identifiable {
    case flac = "flac"
    case alac = "alac"
    case aac = "aac"
    case pcm16 = "pcm_s16le"
    case pcm24 = "pcm_s24le"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flac: return "FLAC (推奨)"
        case .alac: return "ALAC (Apple Lossless)"
        case .aac: return "AAC"
        case .pcm16: return "PCM 16bit"
        case .pcm24: return "PCM 24bit"
        }
    }

    var description: String {
        switch self {
        case .flac: return "可逆圧縮、ファイルサイズ削減"
        case .alac: return "Apple Lossless、Appleエコシステム向け"
        case .aac: return "非可逆圧縮、高い互換性"
        case .pcm16: return "非圧縮、最大互換性"
        case .pcm24: return "非圧縮、高音質"
        }
    }

    /// ビットレート設定が必要なコーデックかどうか
    var requiresBitrate: Bool {
        switch self {
        case .aac: return true
        default: return false
        }
    }
}

/// AACビットレートの選択肢
enum AudioBitrate: Int, CaseIterable, Identifiable {
    case kbps128 = 128
    case kbps192 = 192
    case kbps256 = 256
    case kbps320 = 320

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue) kbps"
    }

    /// FFmpegに渡す値（例: "256k"）
    var ffmpegValue: String {
        "\(rawValue)k"
    }
}

/// エクスポート設定
struct ExportSettings {
    var audioCodec: AudioCodec = .flac
    var audioBitrate: AudioBitrate = .kbps256
    var offsetSeconds: Double = 0.0
    var outputDirectory: URL?

    /// 自動フェード有効（ぶつ切りノイズ対策）
    var autoFadeEnabled: Bool = true

    /// フェード時間（秒）- 固定値10ms
    static let fadeSeconds: Double = 0.01

    /// 出力ファイル名を生成
    func outputFileName(from inputURL: URL) -> String {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        return "\(baseName)_replaced.mp4"
    }

    /// 出力先URLを生成
    func outputURL(from inputURL: URL) -> URL {
        let fileName = outputFileName(from: inputURL)
        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
        return directory.appendingPathComponent(fileName)
    }
}
