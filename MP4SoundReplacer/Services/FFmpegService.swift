import Foundation

/// FFmpegサービスエラー
enum FFmpegError: LocalizedError {
    case binaryNotFound
    case executionFailed(String)
    case invalidOutput
    case timeout(TimeInterval)

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
        args += [
            "-map", "0:v",
            "-map", "1:a",
            "-c:v", "copy",
            "-c:a", settings.audioCodec.rawValue
        ]

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
    ///   - progressHandler: 進捗ハンドラ（オプション）
    ///   - timeout: タイムアウト秒数（デフォルト: 60秒）
    @discardableResult
    func execute(
        arguments: [String],
        progressHandler: ((Double) -> Void)? = nil,
        timeout: TimeInterval = defaultTimeout
    ) async throws -> String {
        guard let path = ffmpegPath else {
            print("[FFmpeg] Error: Binary not found")
            throw FFmpegError.binaryNotFound
        }

        print("[FFmpeg] Executing with timeout: \(timeout)s")
        print("[FFmpeg] Command: \(path) \(arguments.joined(separator: " "))")

        return try await withThrowingTaskGroup(of: String.self) { group in
            // メインの実行タスク
            group.addTask {
                print("[FFmpeg] Starting process task...")
                let result = try await self.executeProcess(path: path, arguments: arguments)
                print("[FFmpeg] Process task completed")
                return result
            }

            // タイムアウトタスク
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                print("[FFmpeg] Timeout reached after \(timeout)s")
                throw FFmpegError.timeout(timeout)
            }

            // 最初に完了したタスクの結果を返す
            let result = try await group.next()!
            print("[FFmpeg] Task group completed, cancelling remaining tasks")
            group.cancelAll()
            return result
        }
    }

    /// プロセスを実行して結果を返す（内部メソッド）
    private func executeProcess(path: String, arguments: [String]) async throws -> String {
        print("[FFmpeg] executeProcess: Creating process...")

        // プロセスを先に作成（キャンセルハンドラからアクセスするため）
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // ProcessManagerに登録（アプリ終了時に確実に終了させるため）
        ProcessManager.shared.register(process)
        print("[FFmpeg] executeProcess: Process registered with ProcessManager")

        // タスクキャンセル時にプロセスを終了させる
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resumeOnce = OnceFlag()

                // 出力データを蓄積する変数
                var outputData = Data()
                var errorData = Data()
                let dataLock = NSLock()

                // stdout を非同期で読み取り
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        dataLock.lock()
                        outputData.append(data)
                        dataLock.unlock()
                    }
                }

                // stderr を非同期で読み取り
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        dataLock.lock()
                        errorData.append(data)
                        dataLock.unlock()
                    }
                }

                // プロセス終了時の処理
                process.terminationHandler = { proc in
                    print("[FFmpeg] terminationHandler called, status: \(proc.terminationStatus)")

                    // ProcessManagerから登録解除
                    ProcessManager.shared.unregister(proc)

                    // まずハンドラをクリア（これ以上のコールバックを防ぐ）
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    // 残りのデータを読み取り（ロック外で実行してデッドロック防止）
                    let remainingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let remainingError = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    // ロックを取得してデータを結合
                    dataLock.lock()
                    outputData.append(remainingOutput)
                    errorData.append(remainingError)
                    let finalOutput = String(data: outputData, encoding: .utf8) ?? ""
                    let finalError = String(data: errorData, encoding: .utf8) ?? ""
                    dataLock.unlock()

                    // 一度だけresumeを呼ぶ（二重呼び出し防止）
                    guard resumeOnce.tryRun() else {
                        print("[FFmpeg] resumeOnce already called, skipping")
                        return
                    }

                    // キャンセルによる終了か確認
                    if Task.isCancelled {
                        print("[FFmpeg] Resuming with CancellationError")
                        continuation.resume(throwing: CancellationError())
                    } else if proc.terminationStatus != 0 {
                        print("[FFmpeg] Resuming with error: \(finalError)")
                        continuation.resume(throwing: FFmpegError.executionFailed(finalError))
                    } else {
                        print("[FFmpeg] Resuming with success")
                        continuation.resume(returning: finalOutput)
                    }
                }

                do {
                    try process.run()
                    print("[FFmpeg] Process started successfully, PID: \(process.processIdentifier)")
                } catch {
                    print("[FFmpeg] Process failed to start: \(error)")
                    // プロセス起動失敗時（terminationHandlerは呼ばれない）
                    guard resumeOnce.tryRun() else { return }
                    continuation.resume(throwing: FFmpegError.executionFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            print("[FFmpeg] onCancel called, isRunning: \(process.isRunning)")
            // タスクがキャンセルされたらプロセスを終了
            if process.isRunning {
                process.terminate()
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

        try await execute(arguments: arguments, progressHandler: progressHandler)
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

// MARK: - Private Helpers

extension FFmpegService {
    /// スレッドセーフな1回限りの実行を保証するクラス
    private final class OnceFlag: @unchecked Sendable {
        private var _done = false
        private let lock = NSLock()

        /// 最初の呼び出しのみtrueを返し、以降はfalseを返す
        func tryRun() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _done { return false }
            _done = true
            return true
        }
    }
}
