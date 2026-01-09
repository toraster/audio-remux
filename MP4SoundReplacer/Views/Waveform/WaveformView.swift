import SwiftUI

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

// MARK: - Preview

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
