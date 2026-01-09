import AppKit

/// アプリケーションデリゲート
/// アプリ終了時のクリーンアップ処理を担当
class AppDelegate: NSObject, NSApplicationDelegate {

    /// アプリ終了時に呼ばれる
    func applicationWillTerminate(_ notification: Notification) {
        // 実行中のFFmpegプロセスをすべて終了
        ProcessManager.shared.terminateAll()
    }

    /// 最後のウィンドウが閉じられた後にアプリを終了するかどうか
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
