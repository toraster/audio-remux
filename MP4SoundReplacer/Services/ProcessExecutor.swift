import Foundation

/// 外部プロセス実行の共通エラー
enum ProcessExecutionError: LocalizedError {
    case executionFailed(String)
    case timeout(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "プロセス実行エラー: \(message)"
        case .timeout(let seconds):
            return "タイムアウト（\(Int(seconds))秒）"
        }
    }
}

/// 外部プロセス実行サービス
enum ProcessExecutor {
    /// プロセスを実行（タイムアウト付き）
    /// - Parameters:
    ///   - path: 実行ファイルのパス
    ///   - arguments: 引数
    ///   - timeout: タイムアウト秒数
    ///   - category: ログカテゴリ
    /// - Returns: 標準出力の内容
    static func execute(
        path: String,
        arguments: [String],
        timeout: TimeInterval,
        category: LogCategory
    ) async throws -> String {
        Logger.debug("Executing with timeout: \(timeout)s", category: category)
        Logger.debug("Command: \(path) \(arguments.joined(separator: " "))", category: category)

        return try await withThrowingTaskGroup(of: String.self) { group in
            // メインの実行タスク
            group.addTask {
                Logger.debug("Starting process task...", category: category)
                let result = try await executeProcess(path: path, arguments: arguments, category: category)
                Logger.debug("Process task completed", category: category)
                return result
            }

            // タイムアウトタスク
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                Logger.debug("Timeout reached after \(timeout)s", category: category)
                throw ProcessExecutionError.timeout(timeout)
            }

            // 最初に完了したタスクの結果を返す
            let result = try await group.next()!
            Logger.debug("Task group completed, cancelling remaining tasks", category: category)
            group.cancelAll()
            return result
        }
    }

    /// プロセスを実行して結果を返す（内部メソッド）
    private static func executeProcess(
        path: String,
        arguments: [String],
        category: LogCategory
    ) async throws -> String {
        Logger.debug("executeProcess: Creating process...", category: category)

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
        Logger.debug("executeProcess: Process registered with ProcessManager", category: category)

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
                    Logger.debug("terminationHandler called, status: \(proc.terminationStatus)", category: category)

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
                        Logger.debug("resumeOnce already called, skipping", category: category)
                        return
                    }

                    // キャンセルによる終了か確認
                    if Task.isCancelled {
                        Logger.debug("Resuming with CancellationError", category: category)
                        continuation.resume(throwing: CancellationError())
                    } else if proc.terminationStatus != 0 {
                        Logger.debug("Resuming with error: \(finalError)", category: category)
                        continuation.resume(throwing: ProcessExecutionError.executionFailed(finalError))
                    } else {
                        Logger.debug("Resuming with success", category: category)
                        continuation.resume(returning: finalOutput)
                    }
                }

                do {
                    try process.run()
                    Logger.debug("Process started successfully, PID: \(process.processIdentifier)", category: category)
                } catch {
                    Logger.error("Process failed to start: \(error)", category: category)
                    // プロセス起動失敗時（terminationHandlerは呼ばれない）
                    guard resumeOnce.tryRun() else { return }
                    continuation.resume(throwing: ProcessExecutionError.executionFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            Logger.debug("onCancel called, isRunning: \(process.isRunning)", category: category)
            // タスクがキャンセルされたらプロセスを終了
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

// MARK: - OnceFlag

/// スレッドセーフな1回限りの実行を保証するクラス
final class OnceFlag: @unchecked Sendable {
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
