import SwiftUI

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

// MARK: - WaveformBarsShape

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
