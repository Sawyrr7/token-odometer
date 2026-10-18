import SwiftUI
import OdometerCore

/// One mechanical wheel. `position` is an ever-increasing integer during normal use; the wheel
/// shows `position % 10`, and animating between integers rolls it forward through 9 → 0.
struct RollingDigit: View, Animatable {
    var position: Double
    let fontSize: CGFloat
    let inverted: Bool

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        let height = fontSize * 1.3
        let whole = floor(position)
        let fraction = position - whole
        let digit = Int(whole.truncatingRemainder(dividingBy: 10))

        ZStack {
            face(digit).offset(y: -fraction * height)
            face((digit + 1) % 10).offset(y: (1 - fraction) * height)
        }
        .frame(width: fontSize * 0.72, height: height)
        .background(inverted ? Palette.wheelInverted : Palette.wheel)
        .overlay(LinearGradient(
            stops: [.init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .clear, location: 0.7),
                    .init(color: .black.opacity(0.55), location: 1)],
            startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: fontSize * 0.12))
    }

    private func face(_ digit: Int) -> some View {
        Text(String(digit))
            .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(inverted ? Palette.digitInverted : Palette.digit)
    }
}

struct OdometerView: View {
    let position: Int
    let digits: Int
    let fontSize: CGFloat

    var body: some View {
        let wheels = Odometer(digits: digits).wheels(position: position)
        HStack(spacing: max(1, fontSize * 0.1)) {
            ForEach(Array(wheels.enumerated()), id: \.offset) { index, wheel in
                RollingDigit(position: Double(wheel), fontSize: fontSize, inverted: index == wheels.count - 1)
            }
        }
        .padding(.horizontal, fontSize * 0.2)
        .padding(.vertical, fontSize * 0.12)
        .background(RoundedRectangle(cornerRadius: fontSize * 0.25).fill(Palette.bezel))
    }
}

enum Palette {
    static let wheel = Color(white: 0.1)
    static let digit = Color(white: 0.95)
    static let wheelInverted = Color(white: 0.93)
    static let digitInverted = Color(red: 0.75, green: 0.1, blue: 0.08)
    static let bezel = Color(white: 0.02)
    static let dash = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let accent = Color(red: 1.0, green: 0.48, blue: 0.12)
    static let dim = Color(white: 0.55)
}
