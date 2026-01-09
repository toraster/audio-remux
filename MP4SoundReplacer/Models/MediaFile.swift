import Foundation

/// メディアファイルの種類
enum MediaFileType {
    case video
    case audio
}

/// メディアファイル情報
struct MediaFile: Identifiable {
    let id = UUID()
    let url: URL
    let type: MediaFileType

    // メタデータ（FFprobeで取得）
    var duration: TimeInterval?
    var videoCodec: String?
    var audioCodec: String?
    var sampleRate: Int?
    var channels: Int?
    var width: Int?
    var height: Int?
    var frameRate: Double?
    var bitRate: Int?
    var fileSize: Int64?

    var fileName: String {
        url.lastPathComponent
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    /// 動画ファイルかどうか
    var isVideo: Bool {
        type == .video
    }

    /// 音声ファイルかどうか
    var isAudio: Bool {
        type == .audio
    }

    /// フォーマット済みの長さ表示
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    /// フォーマット済みファイルサイズ表示
    var formattedFileSize: String? {
        guard let size = fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// フォーマット済みチャンネル数表示
    var formattedChannels: String? {
        guard let channels = channels else { return nil }
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return "\(channels)ch"
        }
    }

    /// フォーマット済みビットレート表示
    var formattedBitRate: String? {
        guard let bitRate = bitRate else { return nil }
        let kbps = bitRate / 1000
        if kbps >= 1000 {
            let mbps = Double(kbps) / 1000.0
            return String(format: "%.1fMbps", mbps)
        }
        return "\(kbps)kbps"
    }

    /// ファイル情報のサマリー
    var summary: String {
        var parts: [String] = []

        if let duration = formattedDuration {
            parts.append(duration)
        }

        if let fileSize = formattedFileSize {
            parts.append(fileSize)
        }

        if let width = width, let height = height {
            parts.append("\(width)x\(height)")
        }

        if let videoCodec = videoCodec {
            parts.append(videoCodec)
        }

        if let audioCodec = audioCodec {
            parts.append(audioCodec)
        }

        if let sampleRate = sampleRate {
            parts.append("\(sampleRate)Hz")
        }

        if let channels = formattedChannels {
            parts.append(channels)
        }

        if let bitRate = formattedBitRate {
            parts.append(bitRate)
        }

        return parts.joined(separator: " | ")
    }

    /// 対応する動画拡張子
    static let videoExtensions = ["mp4", "m4v", "mov"]

    /// 対応する音声拡張子
    static let audioExtensions = ["wav", "aiff", "aif", "flac"]

    /// URLからMediaFileTypeを推測
    static func detectType(from url: URL) -> MediaFileType? {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) {
            return .video
        } else if audioExtensions.contains(ext) {
            return .audio
        }
        return nil
    }
}
