import SwiftUI

/// The whole gesture in a 5-second loop (§5.7, screen 1): a file slides
/// in, a key is tapped, the wheel opens around it, the file drops on the
/// lit segment and the confirmation pill appears. With "Réduire les
/// animations", a still frame of the open wheel with its segment lit.
struct GestureAnimationView: View {
    private static let loop: TimeInterval = 5
    private static let segments = 6
    private static let litSegment = 1
    /// Centre of the lit segment, from the wheel centre (SwiftUI y grows down).
    private static let dropPoint = CGSize(width: 45, height: -26)

    /// The key that opens the Convert wheel, as remapped in Settings.
    let key: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(key: String = "⇧") {
        self.key = key
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 2.4 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop)
            frame(at: time)
        }
        .frame(width: 260, height: 190)
        // The real wheel is always dark (Theme.hudAppearance): so is its picture.
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.16)))
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("Animation\u{202F}: glisser un fichier, appuyer sur une touche, déposer sur la roue")
    }

    /// 0–1 s slide in · 1–1.3 key · 1.3–3 wheel, segment lit at 2 · 3–3.4 drop ·
    /// 3.6–4.6 pill · then everything fades before the loop restarts.
    private func frame(at time: TimeInterval) -> some View {
        func progress(_ from: TimeInterval, _ to: TimeInterval) -> Double { min(max((time - from) / (to - from), 0), 1) }
        let slide = progress(0, 1)
        let keyDown = (1.0..<1.3).contains(time)
        let wheel = progress(1.3, 1.45) * (1 - progress(3.3, 3.6))
        let drop = progress(3.0, 3.4)
        let pill = progress(3.6, 3.8) * (1 - progress(4.6, 4.9))
        return ZStack {
            ForEach(0..<Self.segments, id: \.self) { index in
                WheelSlice(index: index, count: Self.segments)
                    .fill(index == Self.litSegment && time > 2 ? Theme.accentColor : Color.secondary.opacity(0.25))
            }
            .frame(width: 150, height: 150)
            .scaleEffect(0.92 + 0.08 * wheel)
            .opacity(wheel)

            Image(systemName: "doc.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .scaleEffect(1 - 0.4 * drop)
                .offset(x: -110 * (1 - slide) + Self.dropPoint.width * drop, y: Self.dropPoint.height * drop)
                .opacity(1 - progress(3.3, 3.5))

            Text(key)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(keyDown ? Theme.accentColor.opacity(0.35) : Color.secondary.opacity(0.15)))
                .scaleEffect(keyDown ? 0.9 : 1)
                .offset(x: 105, y: 72)

            HStack(spacing: 6) {
                Image(systemName: "photo")
                Text("photo.png créé")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.18)))
            .offset(x: -10, y: 72 - 6 * (1 - pill))
            .opacity(pill)
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
