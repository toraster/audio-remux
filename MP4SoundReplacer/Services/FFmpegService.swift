import Foundation

/// FFmpegサービスエラー
enum FFmpegError: LocalizedError {
    case binaryNotFound
    case executionFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "FFmpegバイナリが見つかりません。Resources/ffmpegを確認してください。"
        case .executionFailed(let message):
            return "FFmpeg実行エラー: \(message)"
        case .invalidOutput:
            return "無効な出力です"
        }
    }
}

/// FFmpeg実行サービス
class FFmpegService {
    static let shared = FFmpegService()

    private init() {}

    /// FFmpegバイナリのパス
    var ffmpegPath: String? {
        // 1. アプリバンドル内を探す（Xcode配布用）
        if let bundlePath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            return bundlePath
        }

        // 2. 開発時: ソースディレクトリのResourcesを探す
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // MP4SoundReplacer/
            .appendingPathComponent("Resources/ffmpeg")
        if FileManager.default.isExecutableFile(atPath: sourceDir.path) {
            return sourceDir.path
        }

        // 3. Homebrew版FFmpeg
        let homebrewPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        for path in homebrewPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// FFmpegが利用可能かどうか
    var isAvailable: Bool {
        guard let path = ffmpegPath else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// 音声差し替えコマンドの引数を生成
    func buildReplaceAudioArguments(
        videoURL: URL,
        audioURL: URL,
        outputURL: URL,
        settings: ExportSettings
    ) -> [String] {
        var args = ["-y", "-hide_banner"]

        // 正のオフセット: 音声を遅らせる
        if settings.offsetSeconds > 0 {
            args += ["-itsoffset", String(format: "%.3f", settings.offsetSeconds)]
        }

        args += ["-i", videoURL.path]

        // 負のオフセット: 音声の先頭をカット
        if settings.offsetSeconds < 0 {
            args += ["-ss", String(format: "%.3f", -settings.offsetSeconds)]
        }

        args += ["-i", audioURL.path]

        // ストリームマッピングとコーデック設定
        args += [
            "-map", "0:v",
            "-map", "1:a",
            "-c:v", "copy",
            "-c:a", settings.audioCodec.rawValue,
            "-shortest",
            outputURL.path
        ]

        return args
    }

    /// FFmpegコマンドを実行
    @discardableResult
    func execute(
        arguments: [String],
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        guard let path = ffmpegPath else {
            throw FFmpegError.binaryNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FFmpegError.executionFailed(error.localizedDescription))
                return
            }

            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                continuation.resume(throwing: FFmpegError.executionFailed(errorOutput))
            } else {
                continuation.resume(returning: output)
            }
        }
    }

    /// 音声差し替えを実行
    func replaceAudio(
        videoURL: URL,
        audioURL: URL,
        outputURL: URL,
        settings: ExportSettings,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        let arguments = buildReplaceAudioArguments(
            videoURL: videoURL,
            audioURL: audioURL,
            outputURL: outputURL,
            settings: settings
        )

        try await execute(arguments: arguments, progressHandler: progressHandler)
    }

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
        let arguments = [
            "-y",
            "-hide_banner",
            "-i", videoURL.path,
            "-vn",
            "-c:a", "pcm_s16le",
            "-ar", String(sampleRate),
            "-ac", "1",  // モノラルに変換（分析用）
            outputURL.path
        ]

        try await execute(arguments: arguments)
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
        let arguments = [
            "-y",
            "-hide_banner",
            "-i", audioURL.path,
            "-c:a", "pcm_s16le",
            "-ar", String(sampleRate),
            "-ac", "1",  // モノラルに変換（分析用）
            outputURL.path
        ]

        try await execute(arguments: arguments)
    }
}
