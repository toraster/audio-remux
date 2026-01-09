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
        // 1. アプリバンドル内を探す（Xcode配布用）
        if let bundlePath = Bundle.main.path(forResource: "ffprobe", ofType: nil) {
            return bundlePath
        }

        // 2. 開発時: ソースディレクトリのResourcesを探す
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // MP4SoundReplacer/
            .appendingPathComponent("Resources/ffprobe")
        if FileManager.default.isExecutableFile(atPath: sourceDir.path) {
            return sourceDir.path
        }

        // 3. Homebrew版FFprobe
        let homebrewPaths = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
        for path in homebrewPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// FFprobeが利用可能かどうか
    var isAvailable: Bool {
        guard let path = ffprobePath else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
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
        return try await withThrowingTaskGroup(of: String.self) { group in
            // メインの実行タスク
            group.addTask {
                try await self.executeProcess(path: path, arguments: arguments)
            }

            // タイムアウトタスク
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw FFprobeError.timeout(timeout)
            }

            // 最初に完了したタスクの結果を返す
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// プロセスを実行して結果を返す（内部メソッド）
    private func executeProcess(path: String, arguments: [String]) async throws -> String {
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
                    guard resumeOnce.tryRun() else { return }

                    // キャンセルによる終了か確認
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if proc.terminationStatus != 0 {
                        continuation.resume(throwing: FFprobeError.executionFailed(finalError))
                    } else {
                        continuation.resume(returning: finalOutput)
                    }
                }

                do {
                    try process.run()
                } catch {
                    // プロセス起動失敗時（terminationHandlerは呼ばれない）
                    guard resumeOnce.tryRun() else { return }
                    continuation.resume(throwing: FFprobeError.executionFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            // タスクがキャンセルされたらプロセスを終了
            if process.isRunning {
                process.terminate()
            }
        }
    }

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
