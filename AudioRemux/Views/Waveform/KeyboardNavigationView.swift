import SwiftUI

/// キーボードナビゲーション用のNSView（Home/Endキー対応）
struct KeyboardNavigationView: NSViewRepresentable {
    let onHome: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> KeyboardNavigationNSView {
        let view = KeyboardNavigationNSView()
        view.onHome = onHome
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ nsView: KeyboardNavigationNSView, context: Context) {
        nsView.onHome = onHome
        nsView.onEnd = onEnd
    }
}

class KeyboardNavigationNSView: NSView {
    var onHome: (() -> Void)?
    var onEnd: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 115: // Home key
            onHome?()
        case 119: // End key
            onEnd?()
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // クリックでフォーカスを取得
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
