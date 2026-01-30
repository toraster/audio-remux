import Foundation

/// ビット深度の選択肢
enum BitDepth: Int, CaseIterable, Identifiable {
    case bit16 = 16
    case bit24 = 24

    var id: Int { rawValue }
    var displayName: String { "\(rawValue)bit" }
}

/// 出力コンテナフォーマットの選択肢
enum OutputContainer: String, CaseIterable, Identifiable {
    case mp4 = "mp4"
    case mkv = "mkv"
    case mov = "mov"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .mkv: return "MKV"
        case .mov: return "MOV"
        }
    }

    var description: String {
        switch self {
        case .mp4: return "高い互換性、ストリーミング向き"
        case .mkv: return "多機能、全コーデック対応"
        case .mov: return "Apple製品向け、Final Cut Pro互換"
        }
    }

    var fileExtension: String {
        rawValue
    }

    /// このコンテナがサポートする音声コーデック
    var supportedAudioCodecs: [AudioCodec] {
        switch self {
        case .mp4:
            // MP4はPCMを直接サポートしない（ALACは可能）
            return [.flac, .alac, .aac]
        case .mkv:
            // MKVは全てのコーデックをサポート
            return AudioCodec.allCases
        case .mov:
            // MOVはApple系とPCMをサポート
            return [.alac, .aac, .pcm]
        }
    }

    /// 指定されたコーデックがこのコンテナでサポートされているか
    func supports(_ codec: AudioCodec) -> Bool {
        supportedAudioCodecs.contains(codec)
    }

    /// このコンテナで推奨される音声コーデック
    var recommendedCodec: AudioCodec {
        switch self {
        case .mp4: return .alac   // MP4ではALACを推奨（互換性重視）
        case .mkv: return .flac   // MKVではFLACを推奨（可逆圧縮）
        case .mov: return .alac   // MOVではALACを推奨（Apple互換）
        }
    }

    /// コンテナとコーデックの組み合わせに関する警告メッセージ
    func warning(for codec: AudioCodec) -> String? {
        switch (self, codec) {
        case (.mp4, .flac):
            return "MP4+FLACは一部のプレイヤーで再生できません"
        default:
            return nil
        }
    }
}

/// 音声コーデックの選択肢
enum AudioCodec: String, CaseIterable, Identifiable {
    case flac = "flac"
    case alac = "alac"
    case aac = "aac"
    case pcm = "pcm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flac: return "FLAC"
        case .alac: return "ALAC"
        case .aac: return "AAC"
        case .pcm: return "PCM"
        }
    }

    var description: String {
        switch self {
        case .flac: return "可逆圧縮、ファイルサイズ削減"
        case .alac: return "Apple Lossless、Appleエコシステム向け"
        case .aac: return "非可逆圧縮、高い互換性"
        case .pcm: return "非圧縮、最大互換性"
        }
    }

    /// ビットレート設定が必要なコーデックかどうか
    var requiresBitrate: Bool {
        switch self {
        case .aac: return true
        default: return false
        }
    }

    /// ビット深度設定が有効なコーデックかどうか
    var supportsBitDepth: Bool {
        switch self {
        case .flac, .alac, .pcm: return true
        case .aac: return false
        }
    }

    /// FFmpegに渡すコーデック名を取得
    func ffmpegCodecName(bitDepth: BitDepth) -> String {
        switch self {
        case .flac:
            return "flac"
        case .alac:
            return "alac"
        case .aac:
            return "aac"
        case .pcm:
            switch bitDepth {
            case .bit16: return "pcm_s16le"
            case .bit24: return "pcm_s24le"
            }
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
    var audioBitDepth: BitDepth = .bit24
    var audioBitrate: AudioBitrate = .kbps256
    var offsetSeconds: Double = 0.0
    var outputDirectory: URL?

    /// 出力コンテナフォーマット
    var outputContainer: OutputContainer = .mp4

    /// 出力ファイル名サフィックス（空の場合は "_replaced"）
    var outputSuffix: String = "_replaced"

    /// 自動フェード有効（ぶつ切りノイズ対策）
    var autoFadeEnabled: Bool = true

    /// フェード時間（秒）- 固定値10ms
    static let fadeSeconds: Double = 0.01

    /// デフォルトのサフィックス
    static let defaultSuffix: String = "_replaced"

    /// 実際に使用するサフィックス（空の場合はデフォルト値を返す）
    var effectiveSuffix: String {
        outputSuffix.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultSuffix : outputSuffix
    }

    /// 出力ファイル名を生成
    func outputFileName(from inputURL: URL) -> String {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        return "\(baseName)\(effectiveSuffix).\(outputContainer.fileExtension)"
    }

    /// 出力先URLを生成
    func outputURL(from inputURL: URL) -> URL {
        let fileName = outputFileName(from: inputURL)
        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
        return directory.appendingPathComponent(fileName)
    }

    /// 現在の設定が有効かどうか（コンテナとコーデックの互換性）
    var isValidCombination: Bool {
        outputContainer.supports(audioCodec)
    }

    /// コンテナ変更時に互換性のあるコーデックに自動調整
    mutating func adjustCodecForContainer() {
        if !outputContainer.supports(audioCodec) {
            // 互換性のない場合は、コンテナがサポートする最初のコーデックに変更
            if let firstSupported = outputContainer.supportedAudioCodecs.first {
                audioCodec = firstSupported
            }
        }
    }
}
