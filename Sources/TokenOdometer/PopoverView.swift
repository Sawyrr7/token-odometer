import SwiftUI
import OdometerCore

struct MenuBarOdometer: View {
    let model: OdometerModel

    var body: some View {
        OdometerView(position: model.lifetime, digits: OdometerModel.lifetimeDigits, fontSize: 12)
            .animation(.easeInOut(duration: model.loaded ? 1.2 : 0), value: model.lifetime)
    }
}

struct PopoverView: View {
    @Bindable var model: OdometerModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("TOKEN ODOMETER").font(.system(size: 11, weight: .heavy)).tracking(2)
                Spacer()
                Text(Date.now, format: .dateTime.weekday(.abbreviated).month().day())
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.dim)
            }

            VStack(spacing: 6) {
                OdometerView(position: model.lifetime, digits: OdometerModel.lifetimeDigits, fontSize: 24)
                    .animation(.easeInOut(duration: 1.6), value: model.lifetime)
                Text(model.loaded ? "\(model.lifetime.formatted()) tokens, all time" : "Reading transcripts…")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.dim)
            }

            meter("TODAY", detail: "\(model.todayTotal.formatted()) tokens",
                  position: model.position, animateOn: model.position)

            Speedometer(tokensPerMinute: model.speed)
                .animation(.spring(duration: 0.9, bounce: 0.35), value: model.speed)

            Divider().overlay(Color.white.opacity(0.1))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                row("Input", model.today.input)
                row("Output", model.today.output)
                row("Cache write", model.today.cacheCreation)
                row("Cache read", model.today.cacheRead, dimmed: !model.includeCacheReads)
            }

            ModelBars(byModel: model.todayByModel, includeCacheReads: model.includeCacheReads)

            Divider().overlay(Color.white.opacity(0.1))

            HStack(alignment: .center) {
                meter("TRIP A", detail: "since \(model.tripStart.formatted(.dateTime.month().day().hour().minute()))",
                      position: model.tripTotal, animateOn: model.tripTotal)
                Button("Reset") { model.resetTrip() }
                    .controlSize(.small)
            }

            HStack(spacing: 12) {
                Toggle("Count cache reads", isOn: $model.includeCacheReads)
                    .toggleStyle(.checkbox).font(.system(size: 11))
                Toggle("Open at login", isOn: $model.opensAtLogin)
                    .toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 330)
        .foregroundStyle(Palette.digit)
        .background(Palette.dash)
        .environment(\.colorScheme, .dark)
    }

    private func meter(_ title: String, detail: String, position: Int, animateOn value: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10, weight: .heavy)).tracking(1.5)
                Text(detail).font(.system(size: 10)).foregroundStyle(Palette.dim)
            }
            Spacer()
            OdometerView(position: position, digits: model.odometer.digits, fontSize: 13)
                .animation(.easeInOut(duration: 1.2), value: value)
        }
    }

    private func row(_ label: String, _ value: Int, dimmed: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(Palette.dim)
            Spacer()
            Text(value.formatted()).monospacedDigit()
                .foregroundStyle(dimmed ? Palette.dim : Palette.digit)
                .gridColumnAlignment(.trailing)
        }
        .font(.system(size: 12))
    }
}

/// A half-dial with a needle. The scale is square-rooted so an idle crawl still moves the needle.
struct Speedometer: View {
    let tokensPerMinute: Double
    static let maxScale = 200_000.0

    var body: some View {
        let fraction = min(1, (max(0, tokensPerMinute) / Self.maxScale).squareRoot())
        VStack(spacing: 2) {
            ZStack {
                ForEach(0..<11) { tick in
                    Capsule()
                        .fill(tick >= 8 ? Color.red.opacity(0.85) : Color.white.opacity(0.5))
                        .frame(width: 2, height: tick % 5 == 0 ? 10 : 6)
                        .offset(y: -52)
                        .rotationEffect(.degrees(-90 + Double(tick) * 18))
                }
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: 3, height: 50)
                    .offset(y: -25)
                    .rotationEffect(.degrees(-90 + fraction * 180))
                    .shadow(color: Palette.accent.opacity(0.6), radius: 4)
                Circle().fill(Color(white: 0.85)).frame(width: 10, height: 10)
            }
            .frame(width: 130, height: 130)
            .frame(height: 72, alignment: .top)
            .clipped()

            Text(Self.label(tokensPerMinute))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
            Text("tokens / min").font(.system(size: 10)).foregroundStyle(Palette.dim)
        }
    }

    static func label(_ value: Double) -> String {
        switch value {
        case ..<1_000: return String(Int(value))
        case ..<1_000_000: return String(format: "%.1fk", value / 1_000)
        default: return String(format: "%.2fM", value / 1_000_000)
        }
    }
}

struct ModelBars: View {
    let byModel: [ModelFamily: TokenCounts]
    let includeCacheReads: Bool

    var body: some View {
        let totals = ModelFamily.allCases
            .map { ($0, byModel[$0]?.total(includingCacheReads: includeCacheReads) ?? 0) }
            .filter { $0.1 > 0 }
        let sum = max(1, totals.reduce(0) { $0 + $1.1 })
        if !totals.isEmpty {
            VStack(spacing: 5) {
                ForEach(totals, id: \.0) { family, value in
                    HStack(spacing: 8) {
                        Text(family.label).font(.system(size: 11)).foregroundStyle(Palette.dim)
                            .frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(Palette.accent)
                                    .frame(width: max(4, geo.size.width * Double(value) / Double(sum)))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int((Double(value) / Double(sum) * 100).rounded()))%")
                            .font(.system(size: 11)).monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }
}
