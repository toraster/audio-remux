import Foundation

/// FFmpegなどの外部プロセスを管理するシングルトン
/// アプリ終了時にすべての実行中プロセスを終了させる
final class ProcessManager {
    static let shared = ProcessManager()

    private var runningProcesses: Set<Process> = []
    private let lock = NSLock()

    private init() {}

    /// プロセスを登録
    func register(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        runningProcesses.insert(process)
    }

    /// プロセスを登録解除
    func unregister(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        runningProcesses.remove(process)
    }

    /// すべての実行中プロセスを終了
    func terminateAll() {
        lock.lock()
        let processes = runningProcesses
        lock.unlock()

        for process in processes {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// 実行中のプロセス数
    var runningCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return runningProcesses.filter { $0.isRunning }.count
    }
}
