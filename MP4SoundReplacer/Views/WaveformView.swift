import SwiftUI

/// ズーム可能な波形表示ビュー
struct ZoomableWaveformView: View {
    let waveform: WaveformData?
    let color: Color
    let label: String
    let duration: TimeInterval

    /// ズームレベル（1.0 = 全体表示、200.0 = 最大ズーム）
    @Binding var zoomLevel: Double

    /// 表示開始位置（秒）
    @Binding var scrollPosition: Double

    /// ドラッグによるオフセット調整を有効にするか
    var isDraggable: Bool = false

    /// オフセット値（ドラッグ時に更新）
    @Binding var offsetSeconds: Double

    /// 最大表示時間（スクロール制限用）
    var maxDuration: TimeInterval = 0

    /// カーソル位置（秒）。nilの場合はカーソル非表示
    @Binding var cursorPosition: Double?

    /// ドラッグ中の一時オフセット（秒単位）
    @State private var dragOffsetSeconds: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ラベルと情報
            headerView

            // 波形 + タイムライン
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // タイムライン
                    TimelineView(
                        duration: duration,
                        zoomLevel: zoomLevel,
                        scrollPosition: scrollPosition,
                        width: geometry.size.width
                    )
                    .frame(height: 16)

                    // 波形エリア
                    waveformArea(geometry: geometry)
                }
            }
            .frame(height: 96)
        }
    }

    private var headerView: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if waveform != nil {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func waveformArea(geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let effectiveDuration = maxDuration > 0 ? maxDuration : duration
        let visibleDuration = effectiveDuration / zoomLevel
        let pixelsPerSecond = width / visibleDuration

        return ZStack(alignment: .leading) {
            if let waveform = waveform {
                // ドラッグ可能な波形はオフセットを考慮
                let totalOffset = isDraggable ? (offsetSeconds + dragOffsetSeconds) : 0

                // 波形データの取得範囲（オフセットを考慮）
                // 画面上の scrollPosition に表示されるべき波形の時間 = scrollPosition - totalOffset
                let dataStartTime = max(0, scrollPosition - totalOffset)
                let dataEndTime = min(duration, scrollPosition + visibleDuration - totalOffset)

                // サンプルの取得（取得範囲が有効な場合のみ）
                if dataStartTime < dataEndTime {
                    let samples = waveform.samples(from: dataStartTime, to: dataEndTime)

                    // 取得したデータの時間幅に対応するピクセル幅
                    let dataWidth = CGFloat((dataEndTime - dataStartTime) * pixelsPerSecond)
                    let downsampled = downsample(samples, to: max(1, Int(dataWidth)))

                    // 描画位置: dataStartTime が画面上のどこに表示されるか
                    // dataStartTime の画面位置 = (dataStartTime + totalOffset - scrollPosition) * pixelsPerSecond
                    let drawOffset = CGFloat((dataStartTime + totalOffset - scrollPosition) * pixelsPerSecond)

                    WaveformCanvas(samples: downsampled, color: color)
                        .frame(width: dataWidth, height: 80)
                        .offset(x: drawOffset)
                }
            }

            // プレースホルダー（波形がない場合）
            if waveform == nil {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Text("波形なし")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
            }

            // タイムラインカーソル（縦線）
            if let cursor = cursorPosition {
                let relativeTime = cursor - scrollPosition
                if relativeTime >= 0 && relativeTime <= visibleDuration {
                    let xPosition = CGFloat(relativeTime / visibleDuration) * width
                    TimelineCursorView(cursorTime: cursor)
                        .position(x: xPosition, y: 30)
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 80)
        .clipped()
        .overlay(
            // クリック＆ドラッグ検出
            WaveformInteractionView(
                isDraggable: isDraggable,
                width: width,
                visibleDuration: visibleDuration,
                scrollPosition: scrollPosition,
                effectiveDuration: effectiveDuration,
                onCursorSet: { xPosition in
                    let clickedTime = scrollPosition + (Double(xPosition) / Double(width)) * visibleDuration
                    cursorPosition = max(0, min(effectiveDuration, clickedTime))
                },
                onDragChanged: { dragDelta in
                    let secondsPerPixel = visibleDuration / Double(width)
                    dragOffsetSeconds = Double(dragDelta) * secondsPerPixel
                },
                onDragEnded: {
                    offsetSeconds += dragOffsetSeconds
                    dragOffsetSeconds = 0
                }
            )
        )
        .onScrollGesture { delta, event, mouseXRatio in
            handleScroll(delta: delta, event: event, mouseXRatio: mouseXRatio, width: width)
        }
    }

    private func handleScroll(delta: CGFloat, event: NSEvent, mouseXRatio: CGFloat, width: CGFloat) {
        // Shiftキーでスクロール、通常はズーム
        if event.modifierFlags.contains(.shift) || abs(event.deltaX) > abs(event.deltaY) {
            // 水平スクロール
            let effectiveDuration = maxDuration > 0 ? maxDuration : duration
            let visibleDuration = effectiveDuration / zoomLevel
            let scrollDelta = Double(event.deltaX) * visibleDuration * 0.01
            let maxScroll = max(0, effectiveDuration - visibleDuration)
            scrollPosition = max(0, min(maxScroll, scrollPosition - scrollDelta))
        } else {
            // ズーム（マウス位置を基準点として）
            let effectiveDuration = maxDuration > 0 ? maxDuration : duration
            let oldVisibleDuration = effectiveDuration / zoomLevel

            // マウス位置の時間を計算
            let clampedRatio = min(1.0, max(0.0, Double(mouseXRatio)))
            let mouseTime = scrollPosition + (clampedRatio * oldVisibleDuration)

            // 新しいズームレベルを計算（上限200倍）
            let zoomFactor = 1.0 + Double(delta) * 0.05
            let newZoom = max(1.0, min(200.0, zoomLevel * zoomFactor))
            let newVisibleDuration = effectiveDuration / newZoom

            // マウス位置が同じ相対位置に留まるようにスクロール位置を調整
            let newScrollPosition = mouseTime - (clampedRatio * newVisibleDuration)
            let maxScroll = max(0, effectiveDuration - newVisibleDuration)

            zoomLevel = newZoom
            scrollPosition = max(0, min(maxScroll, newScrollPosition))
        }
    }

    private func downsample(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard targetCount > 0, samples.count > targetCount else {
            return samples
        }

        let ratio = Float(samples.count) / Float(targetCount)
        var result = [Float](repeating: 0, count: targetCount)

        for i in 0..<targetCount {
            let startIndex = Int(Float(i) * ratio)
            let endIndex = min(Int(Float(i + 1) * ratio), samples.count)

            var maxAbs: Float = 0
            for j in startIndex..<endIndex {
                let absValue = abs(samples[j])
                if absValue > maxAbs {
                    maxAbs = absValue
                    result[i] = samples[j]
                }
            }
        }

        return result
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }
}

/// タイムライン表示
struct TimelineView: View {
    let duration: TimeInterval
    let zoomLevel: Double
    let scrollPosition: Double
    let width: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))

                // 目盛りと時間ラベル
                ForEach(tickPositions, id: \.position) { tick in
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 1, height: tick.isMajor ? 8 : 4)

                        if tick.isMajor && shouldShowLabel(at: tick.position) {
                            Text(formatTime(tick.time))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                    }
                    .position(x: tick.position, y: 8)
                }
            }
        }
    }

    private var tickPositions: [TickMark] {
        let visibleDuration = duration / zoomLevel
        let endTime = min(scrollPosition + visibleDuration, duration)

        // ズームレベルに応じた目盛り間隔
        let interval = tickInterval(for: visibleDuration)
        let majorInterval = interval * 5

        var ticks: [TickMark] = []

        // 開始位置を間隔に揃える
        let startTick = ceil(scrollPosition / interval) * interval

        var time = startTick
        while time <= endTime {
            let relativeTime = time - scrollPosition
            let position = CGFloat(relativeTime / visibleDuration) * width

            if position >= 0 && position <= width {
                let isMajor = time.truncatingRemainder(dividingBy: majorInterval) < 0.001
                ticks.append(TickMark(time: time, position: position, isMajor: isMajor))
            }

            time += interval
        }

        return ticks
    }

    private func tickInterval(for visibleDuration: TimeInterval) -> TimeInterval {
        // 表示幅に約10〜20個の目盛りが表示されるよう調整
        let targetTicks = 15.0
        let rawInterval = visibleDuration / targetTicks

        // 適切な間隔に丸める（200倍ズーム対応: より細かい間隔を追加）
        let intervals: [TimeInterval] = [
            0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05,
            0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0
        ]
        return intervals.first { $0 >= rawInterval } ?? 60.0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    /// 左端・右端付近のラベルは非表示（はみ出し防止）
    private func shouldShowLabel(at position: CGFloat) -> Bool {
        let labelHalfWidth: CGFloat = 22  // "0:00.00" の半分程度
        return position >= labelHalfWidth && position <= width - labelHalfWidth
    }

    struct TickMark: Hashable {
        let time: TimeInterval
        let position: CGFloat
        let isMajor: Bool

        func hash(into hasher: inout Hasher) {
            hasher.combine(position)
        }
    }
}

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
}

extension View {
    func onScrollGesture(action: @escaping (CGFloat, NSEvent, CGFloat) -> Void) -> some View {
        modifier(ScrollGestureModifier(action: action))
    }
}

/// 波形描画キャンバス（macOS 11.0互換）
struct WaveformCanvas: View {
    let samples: [Float]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let centerY = height / 2

            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(NSColor.controlBackgroundColor).opacity(0.6),
                                Color(NSColor.controlBackgroundColor).opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color.opacity(0.15), lineWidth: 1)
                    )

                // 中央線
                Path { path in
                    path.move(to: CGPoint(x: 8, y: centerY))
                    path.addLine(to: CGPoint(x: width - 8, y: centerY))
                }
                .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // 波形バー
                if !samples.isEmpty {
                    WaveformBarsShape(samples: samples)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
    }
}

/// 波形バーのシェイプ
struct WaveformBarsShape: Shape {
    let samples: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard !samples.isEmpty else { return path }

        let width = rect.width
        let height = rect.height
        let centerY = height / 2
        let barWidth = max(1, width / CGFloat(samples.count))

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * barWidth
            let amplitude = CGFloat(abs(sample)) * centerY

            let barRect = CGRect(
                x: x,
                y: centerY - amplitude,
                width: max(1, barWidth - 0.5),
                height: max(1, amplitude * 2)
            )

            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: 0.5, height: 0.5))
        }

        return path
    }
}

/// タイムラインカーソル（プレイヘッド風縦線）
struct TimelineCursorView: View {
    let cursorTime: Double

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // 上部ハンドル（下向き三角形）
            CursorHandleShape()
                .fill(Color.white.opacity(0.9))
                .frame(width: 10, height: 6)

            // 縦線
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color.white.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1.5, height: 48)

            // 時間表示（ホバー時）
            if isHovered {
                Text(formatCursorTime(cursorTime))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.8))
                    )
                    .offset(y: 2)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func formatCursorTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        if minutes > 0 {
            return String(format: "%d:%06.3f", minutes, seconds)
        } else {
            return String(format: "%.3fs", seconds)
        }
    }
}

/// カーソルハンドル形状（下向き三角形）
struct CursorHandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

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
}

/// シンプルな波形表示（後方互換用）
struct WaveformView: View {
    let waveform: WaveformData?
    let color: Color
    let label: String
    var offset: TimeInterval = 0

    var body: some View {
        ZoomableWaveformView(
            waveform: waveform,
            color: color,
            label: label,
            duration: waveform?.duration ?? 0,
            zoomLevel: .constant(1.0),
            scrollPosition: .constant(0),
            isDraggable: false,
            offsetSeconds: .constant(0),
            maxDuration: waveform?.duration ?? 0,
            cursorPosition: .constant(nil)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        ZoomableWaveformView(
            waveform: WaveformData(
                samples: (0..<1000).map { _ in Float.random(in: -0.8...0.8) },
                sampleRate: 100,
                duration: 120.5
            ),
            color: .blue,
            label: "元動画の音声",
            duration: 120.5,
            zoomLevel: .constant(2.0),
            scrollPosition: .constant(0),
            isDraggable: false,
            offsetSeconds: .constant(0),
            maxDuration: 120.5,
            cursorPosition: .constant(60.0)
        )

        ZoomableWaveformView(
            waveform: WaveformData(
                samples: (0..<1000).map { _ in Float.random(in: -0.8...0.8) },
                sampleRate: 100,
                duration: 120.5
            ),
            color: .green,
            label: "置換音声（ドラッグ可能）",
            duration: 120.5,
            zoomLevel: .constant(2.0),
            scrollPosition: .constant(0),
            isDraggable: true,
            offsetSeconds: .constant(0.5),
            maxDuration: 120.5,
            cursorPosition: .constant(60.0)
        )
    }
    .padding()
    .frame(width: 600, height: 250)
}
