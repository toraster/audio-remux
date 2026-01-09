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
