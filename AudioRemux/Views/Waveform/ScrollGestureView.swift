import SwiftUI

/// スクロールジェスチャーのビューモディファイア
struct ScrollGestureModifier: ViewModifier {
    let action: (CGFloat, NSEvent, CGFloat) -> Void

    func body(content: Content) -> some View {
        content.overlay(
            ScrollGestureView(action: action)
                .allowsHitTesting(true)
        )
    }
}

/// NSViewを使ったスクロールジェスチャー検出
struct ScrollGestureView: NSViewRepresentable {
    let action: (CGFloat, NSEvent, CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollDetectorView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? ScrollDetectorView {
            view.action = action
        }
    }
}

// MARK: - ScrollDetectorView

class ScrollDetectorView: NSView {
    var action: ((CGFloat, NSEvent, CGFloat) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect
        ]

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )

        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let xRatio = bounds.width > 0 ? localPoint.x / bounds.width : 0.5
        action?(event.deltaY, event, xRatio)
    }
}

// MARK: - View Extension

extension View {
    func onScrollGesture(action: @escaping (CGFloat, NSEvent, CGFloat) -> Void) -> some View {
        modifier(ScrollGestureModifier(action: action))
    }
}
