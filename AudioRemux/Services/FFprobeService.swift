import Foundation

/// FFprobeサービスエラー
enum FFprobeError: LocalizedError {
    case binaryNotFound
    case executionFailed(String)
    case parseError
    case timeout(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "FFprobeバイナリが見つかりません。Resources/ffprobeを確認してください。"
        case .executionFailed(let message):
            return "FFprobe実行エラー: \(message)"
        case .parseError:
            return "メディア情報の解析に失敗しました"
        case .timeout(let seconds):
            return "メディア情報の取得がタイムアウトしました（\(Int(seconds))秒）"
        }
    }
}

/// FFprobe JSON出力の構造
private struct FFprobeOutput: Decodable {
    let streams: [FFprobeStream]
    let format: FFprobeFormat?
}

private struct FFprobeStream: Decodable {
    let codecType: String?
    let codecName: String?
    let width: Int?
    let height: Int?
    let sampleRate: String?
    let channels: Int?
    let rFrameRate: String?
    let duration: String?
    let bitRate: String?

    enum CodingKeys: String, CodingKey {
        case codecType = "codec_type"
        case codecName = "codec_name"
        case width
        case height
        case sampleRate = "sample_rate"
        case channels
        case rFrameRate = "r_frame_rate"
        case duration
        case bitRate = "bit_rate"
    }
}

private struct FFprobeFormat: Decodable {
    let duration: String?
    let bitRate: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case bitRate = "bit_rate"
    }
}

/// FFprobe実行サービス
class FFprobeService {
    static let shared = FFprobeService()

    /// デフォルトタイムアウト（秒）
    static let defaultTimeout: TimeInterval = 30

    private init() {}

    /// FFprobeバイナリのパス
    var ffprobePath: String? {
        let fm = FileManager.default

        // 1. ダウンロード済みFFprobe（Application Support内）
        // isExecutableFileはquarantine属性があるとfalseを返すため、fileExistsを使用
        let downloadedPath = FFmpegDownloadService.shared.ffprobePath
        if fm.fileExists(atPath: downloadedPath.path) {
            return downloadedPath.path
        }

        // 2. アプリバンドル内を探す（Xcode配布用）
        if let bundlePath = Bundle.main.path(forResource: "ffprobe", ofType: nil) {
            return bundlePath
        }

        // 3. 開発時: ソースディレクトリのResourcesを探す
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // AudioRemux/
            .appendingPathComponent("Resources/ffprobe")
        if fm.fileExists(atPath: sourceDir.path) {
            return sourceDir.path
        }

        // 4. Homebrew版FFprobe
        let homebrewPaths = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
        for path in homebrewPaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// FFprobeが利用可能かどうか
    var isAvailable: Bool {
        guard let path = ffprobePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// メディア情報を取得
    func getMediaInfo(url: URL) async throws -> MediaFile {
        // ファイル存在チェック
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FFprobeError.executionFailed("ファイルが見つかりません: \(url.lastPathComponent)")
        }

        guard let path = ffprobePath else {
            throw FFprobeError.binaryNotFound
        }

        let arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_streams",
            "-show_format",
            url.path
        ]

        let output = try await executeFFprobe(path: path, arguments: arguments)

        guard let data = output.data(using: .utf8) else {
            throw FFprobeError.parseError
        }

        let decoder = JSONDecoder()
        let probeOutput: FFprobeOutput
        do {
            probeOutput = try decoder.decode(FFprobeOutput.self, from: data)
        } catch {
            throw FFprobeError.parseError
        }

        return parseMediaFile(url: url, probeOutput: probeOutput)
    }

    /// FFprobeを実行（タイムアウト付き）
    private func executeFFprobe(
        path: String,
        arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) async throws -> String {
        do {
            return try await ProcessExecutor.execute(
                path: path,
                arguments: arguments,
                timeout: timeout,
                category: .ffprobe
            )
        } catch let error as ProcessExecutionError {
            switch error {
            case .executionFailed(let message):
                throw FFprobeError.executionFailed(message)
            case .timeout(let seconds):
                throw FFprobeError.timeout(seconds)
            }
        }
    }

    /// FFprobe出力をMediaFileに変換
    private func parseMediaFile(url: URL, probeOutput: FFprobeOutput) -> MediaFile {
        guard let type = MediaFile.detectType(from: url) else {
            return MediaFile(url: url, type: .video)
        }

        var mediaFile = MediaFile(url: url, type: type)

        // フォーマットから長さを取得
        if let durationStr = probeOutput.format?.duration,
           let duration = Double(durationStr) {
            mediaFile.duration = duration
        }

        // ビットレートを取得
        if let bitRateStr = probeOutput.format?.bitRate,
           let bitRate = Int(bitRateStr) {
            mediaFile.bitRate = bitRate
        }

        // ストリームから詳細情報を取得
        for stream in probeOutput.streams {
            if stream.codecType == "video" {
                mediaFile.videoCodec = stream.codecName
                mediaFile.width = stream.width
                mediaFile.height = stream.height

                // フレームレートを解析 (例: "30000/1001")
                if let rFrameRate = stream.rFrameRate {
                    let parts = rFrameRate.split(separator: "/")
                    if parts.count == 2,
                       let num = Double(parts[0]),
                       let den = Double(parts[1]),
                       den > 0 {
                        mediaFile.frameRate = num / den
                    }
                }

                // ストリームの長さを使用（フォーマットから取得できなかった場合）
                if mediaFile.duration == nil,
                   let durationStr = stream.duration,
                   let duration = Double(durationStr) {
                    mediaFile.duration = duration
                }
            } else if stream.codecType == "audio" {
                mediaFile.audioCodec = stream.codecName
                mediaFile.channels = stream.channels

                if let sampleRateStr = stream.sampleRate,
                   let sampleRate = Int(sampleRateStr) {
                    mediaFile.sampleRate = sampleRate
                }

                // 音声ファイルの場合、ストリームの長さを使用
                if type == .audio && mediaFile.duration == nil,
                   let durationStr = stream.duration,
                   let duration = Double(durationStr) {
                    mediaFile.duration = duration
                }
            }
        }

        // ファイルサイズを取得
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            mediaFile.fileSize = fileSize
        }

        return mediaFile
    }
}
