import SwiftUI

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

// MARK: - CursorHandleShape

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
