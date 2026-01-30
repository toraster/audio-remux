import Foundation

/// FFmpegサービスエラー
enum FFmpegError: LocalizedError {
    case binaryNotFound
    case executionFailed(String)
    case invalidOutput
    case timeout(TimeInterval)
    case incompatibleFormat(container: String, codec: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "FFmpegバイナリが見つかりません。Resources/ffmpegを確認してください。"
        case .executionFailed(let message):
            return "FFmpeg実行エラー: \(message)"
        case .invalidOutput:
            return "無効な出力です"
        case .timeout(let seconds):
            return "処理がタイムアウトしました（\(Int(seconds))秒）"
        case .incompatibleFormat(let container, let codec):
            return "\(container)コンテナは\(codec)コーデックをサポートしていません"
        }
    }
}

/// FFmpeg実行サービス
class FFmpegService {
    static let shared = FFmpegService()

    private init() {}

    /// FFmpegバイナリのパス
    var ffmpegPath: String? {
        let fm = FileManager.default

        // 1. ダウンロード済みFFmpeg（Application Support内）
        // isExecutableFileはquarantine属性があるとfalseを返すため、fileExistsを使用
        let downloadedPath = FFmpegDownloadService.shared.ffmpegPath
        if fm.fileExists(atPath: downloadedPath.path) {
            return downloadedPath.path
        }

        // 2. アプリバンドル内を探す（Xcode配布用）
        if let bundlePath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            return bundlePath
        }

        // 3. 開発時: ソースディレクトリのResourcesを探す
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // AudioRemux/
            .appendingPathComponent("Resources/ffmpeg")
        if fm.fileExists(atPath: sourceDir.path) {
            return sourceDir.path
        }

        // 4. Homebrew版FFmpeg
        let homebrewPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        for path in homebrewPaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// FFmpegが利用可能かどうか
    var isAvailable: Bool {
        guard let path = ffmpegPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// 音声差し替えコマンドの引数を生成
    /// - Parameters:
    ///   - videoURL: 入力動画URL
    ///   - audioURL: 入力音声URL
    ///   - outputURL: 出力URL
    ///   - settings: エクスポート設定
    ///   - videoDuration: 動画の長さ（秒）- 出力長の制御とフェード適用に使用
    func buildReplaceAudioArguments(
        videoURL: URL,
        audioURL: URL,
        outputURL: URL,
        settings: ExportSettings,
        videoDuration: Double? = nil
    ) -> [String] {
        var args = ["-y", "-nostdin", "-hide_banner"]

        // 動画入力（常に最初）
        args += ["-i", videoURL.path]

        // 正のオフセット: 音声を遅らせる（-itsoffsetは音声入力の直前に配置）
        if settings.offsetSeconds > 0 {
            args += ["-itsoffset", String(format: "%.3f", settings.offsetSeconds)]
        }

        // 負のオフセット: 音声の先頭をカット（-ssは音声入力の直前に配置）
        if settings.offsetSeconds < 0 {
            args += ["-ss", String(format: "%.3f", -settings.offsetSeconds)]
        }

        // 音声入力
        args += ["-i", audioURL.path]

        // フェードフィルターの構築
        if settings.autoFadeEnabled, let duration = videoDuration {
            let fadeTime = ExportSettings.fadeSeconds
            let fadeOutStart = max(0, duration - fadeTime)
            let filterStr = String(
                format: "afade=t=in:d=%.3f,afade=t=out:st=%.3f:d=%.3f",
                fadeTime, fadeOutStart, fadeTime
            )
            args += ["-af", filterStr]
        }

        // ストリームマッピングとコーデック設定
        let codecName = settings.audioCodec.ffmpegCodecName(bitDepth: settings.audioBitDepth)
        args += [
            "-map", "0:v",
            "-map", "1:a",
            "-c:v", "copy",
            "-c:a", codecName
        ]

        // ビット深度設定（FLAC/ALACの場合）
        if settings.audioCodec.supportsBitDepth && settings.audioCodec != .pcm {
            let sampleFmt: String
            switch (settings.audioCodec, settings.audioBitDepth) {
            case (.flac, .bit16): sampleFmt = "s16"
            case (.flac, .bit24): sampleFmt = "s32"
            case (.alac, .bit16): sampleFmt = "s16p"
            case (.alac, .bit24): sampleFmt = "s32p"
            default: sampleFmt = "s32"
            }
            args += ["-sample_fmt", sampleFmt]
        }

        // ビットレート設定が必要なコーデックの場合
        if settings.audioCodec.requiresBitrate {
            args += ["-b:a", settings.audioBitrate.ffmpegValue]
        }

        // 負のオフセット時は動画の長さを明示的に指定（-shortestだと音声が短くなった分だけ動画も短くなる）
        if settings.offsetSeconds < 0, let duration = videoDuration {
            args += ["-t", String(format: "%.3f", duration)]
        } else {
            args += ["-shortest"]
        }

        args += [outputURL.path]

        return args
    }

    /// デフォルトタイムアウト（秒）
    static let defaultTimeout: TimeInterval = 60

    /// FFmpegコマンドを実行
    /// - Parameters:
    ///   - arguments: FFmpeg引数
    ///   - timeout: タイムアウト秒数（デフォルト: 60秒）
    @discardableResult
    func execute(
        arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) async throws -> String {
        guard let path = ffmpegPath else {
            Logger.error("Binary not found", category: .ffmpeg)
            throw FFmpegError.binaryNotFound
        }

        do {
            return try await ProcessExecutor.execute(
                path: path,
                arguments: arguments,
                timeout: timeout,
                category: .ffmpeg
            )
        } catch let error as ProcessExecutionError {
            switch error {
            case .executionFailed(let message):
                throw FFmpegError.executionFailed(message)
            case .timeout(let seconds):
                throw FFmpegError.timeout(seconds)
            }
        }
    }

    /// 音声差し替えを実行
    func replaceAudio(
        videoURL: URL,
        audioURL: URL,
        outputURL: URL,
        settings: ExportSettings
    ) async throws {
        // ファイル存在チェック
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw FFmpegError.executionFailed("動画ファイルが見つかりません: \(videoURL.lastPathComponent)")
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw FFmpegError.executionFailed("音声ファイルが見つかりません: \(audioURL.lastPathComponent)")
        }

        // コンテナとコーデックの互換性チェック
        guard settings.outputContainer.supports(settings.audioCodec) else {
            throw FFmpegError.incompatibleFormat(
                container: settings.outputContainer.displayName,
                codec: settings.audioCodec.displayName
            )
        }

        // 動画の長さを取得（フェード適用および負のオフセット時の出力長制御に使用）
        var videoDuration: Double?
        if settings.offsetSeconds < 0 {
            // 負のオフセット時は duration が必須（-shortestだと動画が短くなるため）
            let mediaFile = try await FFprobeService.shared.getMediaInfo(url: videoURL)
            guard let duration = mediaFile.duration else {
                throw FFmpegError.executionFailed("動画の長さを取得できませんでした。負のオフセットを使用するには動画の長さが必要です。")
            }
            videoDuration = duration
        } else if settings.autoFadeEnabled {
            let mediaFile = try? await FFprobeService.shared.getMediaInfo(url: videoURL)
            videoDuration = mediaFile?.duration
        }

        let arguments = buildReplaceAudioArguments(
            videoURL: videoURL,
            audioURL: audioURL,
            outputURL: outputURL,
            settings: settings,
            videoDuration: videoDuration
        )

        try await execute(arguments: arguments)
    }

    /// 音声抽出・変換用の長いタイムアウト（5分）
    static let audioProcessingTimeout: TimeInterval = 300

    /// 動画から音声を抽出（WAV形式）
    /// - Parameters:
    ///   - videoURL: 入力動画のURL
    ///   - outputURL: 出力WAVファイルのURL
    ///   - sampleRate: サンプルレート（デフォルト: 48000Hz）
    func extractAudio(
        from videoURL: URL,
        to outputURL: URL,
        sampleRate: Int = 48000
    ) async throws {
        // ファイル存在チェック
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw FFmpegError.executionFailed("入力ファイルが見つかりません: \(videoURL.lastPathComponent)")
        }

        let arguments = [
            "-y",
            "-nostdin",  // 標準入力を無効化（ハング防止）
            "-hide_banner",
            "-i", videoURL.path,
            "-vn",
            "-c:a", "pcm_s16le",
            "-ar", String(sampleRate),
            "-ac", "1",  // モノラルに変換（分析用）
            outputURL.path
        ]

        try await execute(arguments: arguments, timeout: Self.audioProcessingTimeout)
    }

    /// 音声ファイルをWAV形式に変換
    /// - Parameters:
    ///   - audioURL: 入力音声のURL
    ///   - outputURL: 出力WAVファイルのURL
    ///   - sampleRate: サンプルレート（デフォルト: 48000Hz）
    func convertToWav(
        from audioURL: URL,
        to outputURL: URL,
        sampleRate: Int = 48000
    ) async throws {
        // ファイル存在チェック
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw FFmpegError.executionFailed("入力ファイルが見つかりません: \(audioURL.lastPathComponent)")
        }

        let arguments = [
            "-y",
            "-nostdin",  // 標準入力を無効化（ハング防止）
            "-hide_banner",
            "-i", audioURL.path,
            "-c:a", "pcm_s16le",
            "-ar", String(sampleRate),
            "-ac", "1",  // モノラルに変換（分析用）
            outputURL.path
        ]

        try await execute(arguments: arguments, timeout: Self.audioProcessingTimeout)
    }
}
