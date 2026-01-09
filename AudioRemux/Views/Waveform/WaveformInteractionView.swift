import SwiftUI

/// 波形のクリック＆ドラッグ検出用ビュー
struct WaveformInteractionView: NSViewRepresentable {
    let isDraggable: Bool
    let width: CGFloat
    let visibleDuration: Double
    let scrollPosition: Double
    let effectiveDuration: Double
    let onCursorSet: (CGFloat) -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> WaveformInteractionNSView {
        let view = WaveformInteractionNSView()
        view.isDraggable = isDraggable
        view.onCursorSet = onCursorSet
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: WaveformInteractionNSView, context: Context) {
        nsView.isDraggable = isDraggable
        nsView.onCursorSet = onCursorSet
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }
}

// MARK: - WaveformInteractionNSView

class WaveformInteractionNSView: NSView {
    var isDraggable: Bool = false
    var onCursorSet: ((CGFloat) -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    private var mouseDownTime: Date?
    private var mouseDownLocation: NSPoint?
    private var isDragging: Bool = false

    override func mouseDown(with event: NSEvent) {
        mouseDownTime = Date()
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggable,
              let downLocation = mouseDownLocation else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let dragDelta = currentLocation.x - downLocation.x

        // 5px以上動いたらドラッグと判定
        if abs(dragDelta) > 5 || isDragging {
            isDragging = true
            onDragChanged?(dragDelta)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownTime = nil
            mouseDownLocation = nil
        }

        if isDragging {
            // ドラッグ終了
            isDragging = false
            onDragEnded?()
        } else if let downTime = mouseDownTime,
                  let downLocation = mouseDownLocation {
            // クリック判定
            let upLocation = convert(event.locationInWindow, from: nil)
            let elapsed = Date().timeIntervalSince(downTime)
            let distance = hypot(upLocation.x - downLocation.x, upLocation.y - downLocation.y)

            // 短時間（0.3秒以内）かつ移動距離が小さい（5px以内）場合のみクリック
            if elapsed < 0.3 && distance < 5 {
                onCursorSet?(upLocation.x)
            }
        }
    }
}
