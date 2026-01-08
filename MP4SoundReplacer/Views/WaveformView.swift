import SwiftUI

/// ズーム可能な波形表示ビュー
struct ZoomableWaveformView: View {
    let waveform: WaveformData?
    let color: Color
    let label: String
    let duration: TimeInterval

    /// ズームレベル（1.0 = 全体表示、100.0 = 最大ズーム）
    @Binding var zoomLevel: Double

    /// 表示開始位置（秒）
    @Binding var scrollPosition: Double

    /// ドラッグによるオフセット調整を有効にするか
    var isDraggable: Bool = false

    /// オフセット値（ドラッグ時に更新）
    @Binding var offsetSeconds: Double

    /// ドラッグ中の一時オフセット
    @State private var dragOffset: CGFloat = 0

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
            .frame(height: 76)
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

        return ZStack {
            if let waveform = waveform {
                // 表示範囲の計算
                let visibleDuration = duration / zoomLevel
                let startTime = scrollPosition
                let endTime = min(startTime + visibleDuration, duration)

                // サンプルの取得
                let samples = waveform.samples(from: startTime, to: endTime)
                let downsampled = downsample(samples, to: Int(width))

                WaveformCanvas(samples: downsampled, color: color)
                    .offset(x: isDraggable ? dragOffset : 0)
                    .gesture(isDraggable ? dragGesture(width: width) : nil)
            } else {
                // プレースホルダー
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Text("波形なし")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(height: 60)
        .onScrollGesture { delta in
            handleScrollZoom(delta: delta)
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                // ドラッグ距離を秒に変換
                let visibleDuration = duration / zoomLevel
                let secondsPerPixel = visibleDuration / Double(width)
                let deltaSeconds = Double(value.translation.width) * secondsPerPixel

                offsetSeconds += deltaSeconds
                dragOffset = 0
            }
    }

    private func handleScrollZoom(delta: CGFloat) {
        let zoomFactor = 1.0 + Double(delta) * 0.01
        let newZoom = max(1.0, min(100.0, zoomLevel * zoomFactor))
        zoomLevel = newZoom
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

                        if tick.isMajor {
                            Text(formatTime(tick.time))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
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

        // 適切な間隔に丸める
        let intervals: [TimeInterval] = [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
        return intervals.first { $0 >= rawInterval } ?? 60.0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        if time < 60 {
            return String(format: "%.2f", time)
        } else {
            let minutes = Int(time) / 60
            let seconds = time - Double(minutes * 60)
            return String(format: "%d:%05.2f", minutes, seconds)
        }
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
    let action: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollGestureView(action: action)
        )
    }
}

/// NSViewを使ったスクロールジェスチャー検出
struct ScrollGestureView: NSViewRepresentable {
    let action: (CGFloat) -> Void

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
        var action: ((CGFloat) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            action?(event.deltaY)
        }
    }
}

extension View {
    func onScrollGesture(action: @escaping (CGFloat) -> Void) -> some View {
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
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))

                // 中央線
                Path { path in
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: width, y: centerY))
                }
                .stroke(color.opacity(0.3), lineWidth: 0.5)

                // 波形バー
                if !samples.isEmpty {
                    WaveformBarsShape(samples: samples)
                        .fill(color)
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
            offsetSeconds: .constant(0)
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
            offsetSeconds: .constant(0)
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
            offsetSeconds: .constant(0.5)
        )
    }
    .padding()
    .frame(width: 600, height: 250)
}
