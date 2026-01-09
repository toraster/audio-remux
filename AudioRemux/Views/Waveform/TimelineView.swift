import SwiftUI

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
}

// MARK: - TickMark

struct TickMark: Hashable {
    let time: TimeInterval
    let position: CGFloat
    let isMajor: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(position)
    }
}
