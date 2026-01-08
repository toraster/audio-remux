import SwiftUI

/// 波形表示ビュー
struct WaveformView: View {
    let waveform: WaveformData?
    let color: Color
    let label: String

    /// 表示オフセット（秒）
    var offset: TimeInterval = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ラベル
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let waveform = waveform {
                    Text(formatDuration(waveform.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 波形描画エリア
            GeometryReader { geometry in
                if let waveform = waveform {
                    WaveformCanvas(
                        samples: waveform.downsampled(to: Int(geometry.size.width)),
                        color: color
                    )
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
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
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

#Preview {
    VStack(spacing: 16) {
        WaveformView(
            waveform: nil,
            color: .blue,
            label: "元動画の音声"
        )

        WaveformView(
            waveform: WaveformData(
                samples: (0..<200).map { _ in Float.random(in: -0.8...0.8) },
                sampleRate: 100,
                duration: 120.5
            ),
            color: .green,
            label: "置換音声"
        )
    }
    .padding()
    .frame(width: 500, height: 200)
}
