import SwiftUI

/// The gesture in a 4-second loop (§5.7, screen 1): a file slides in, a
/// key is tapped, the wheel opens around it with a segment lit, then fades.
/// With "Réduire les animations", a still frame of the open wheel.
struct GestureAnimationView: View {
    private static let loop: TimeInterval = 4
    private static let segments = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 2.2 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop)
            frame(at: time)
        }
        .frame(width: 260, height: 180)
        .accessibilityLabel("Animation : glisser un fichier, taper une touche, déposer sur la roue")
    }

    private func frame(at time: TimeInterval) -> some View {
        let slide = min(time / 1, 1)
        let keyDown = (1.0..<1.3).contains(time)
        let wheel = time < 1.3 ? 0 : (time < 3.2 ? min((time - 1.3) / 0.15, 1) : max(1 - (time - 3.2) / 0.3, 0))
        return ZStack {
            ForEach(0..<Self.segments, id: \.self) { index in
                WheelSlice(index: index, count: Self.segments)
                    .fill(index == 1 && time > 2 ? Theme.accentColor : Color.secondary.opacity(0.25))
            }
            .frame(width: 150, height: 150)
            .scaleEffect(0.92 + 0.08 * wheel)
            .opacity(wheel)

            Image(systemName: "doc.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .offset(x: -110 * (1 - slide))

            Text("⇧")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(keyDown ? Theme.accentColor.opacity(0.35) : Color.secondary.opacity(0.15)))
                .scaleEffect(keyDown ? 0.9 : 1)
                .offset(x: 105, y: 70)
        }
    }
}

/// One ring segment, clockwise from the top like the real wheel.
private struct WheelSlice: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.38
        let span = 360.0 / Double(count)
        let start = Angle.degrees(-90 - span / 2 + span * Double(index) + 1.5)
        let end = Angle.degrees(-90 + span / 2 + span * Double(index) - 1.5)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
