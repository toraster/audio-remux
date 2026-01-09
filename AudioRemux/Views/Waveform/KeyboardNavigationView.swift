import SwiftUI

/// キーボードナビゲーション用のビュー（Home/Endキー対応）
/// フォーカスに関係なくキーイベントを検出
struct KeyboardNavigationView: View {
    let onHome: () -> Void
    let onEnd: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                KeyboardMonitor.shared.register(onHome: onHome, onEnd: onEnd)
            }
            .onDisappear {
                KeyboardMonitor.shared.unregister()
            }
    }
}

/// グローバルキーボードモニター
class KeyboardMonitor {
    static let shared = KeyboardMonitor()

    private var monitor: Any?
    private var onHome: (() -> Void)?
    private var onEnd: (() -> Void)?

    private init() {}

    func register(onHome: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onHome = onHome
        self.onEnd = onEnd

        // 既存のモニターがあれば削除
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }

        // ローカルイベントモニターを追加
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            switch event.keyCode {
            case 115: // Home key
                self.onHome?()
                return nil // イベントを消費
            case 119: // End key
                self.onEnd?()
                return nil // イベントを消費
            default:
                return event // 他のイベントはそのまま通す
            }
        }
    }

    func unregister() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        onHome = nil
        onEnd = nil
    }
}
