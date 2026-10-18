import AppKit
import AVFoundation
import SwiftUI
import OdometerCore

/// Renders a share clip: the lifetime odometer rolling from `start` up to `end`, as MP4 + poster PNG.
@MainActor
enum PromoRenderer {
    static let size = CGSize(width: 1600, height: 900)
    static let fps: Int32 = 30
    static let holdStart = 0.6, roll = 4.2, holdEnd = 2.6

    static func render(start: Int, end: Int, since: Date, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let video = dir.appendingPathComponent("token-odometer.mp4")
        try? FileManager.default.removeItem(at: video)

        let writer = try AVAssetWriter(outputURL: video, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let total = Int((holdStart + roll + holdEnd) * Double(fps))
        for frame in 0..<total {
            let t = Double(frame) / Double(fps)
            let progress = ease(min(1, max(0, (t - holdStart) / roll)))
            let image = card(start: start, end: end, progress: progress, since: since)
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            guard let buffer = pixelBuffer(from: image, pool: adaptor.pixelBufferPool) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            if frame == total - 1 { try writePNG(image, to: dir.appendingPathComponent("token-odometer-poster.png")) }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        if let error = writer.error { throw error }
        print("wrote \(video.path)")
    }

    /// Ease-in-out cubic, so the wheels wind up, blur, and settle like a real gauge.
    static func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }

    private static func card(start: Int, end: Int, progress: Double, since: Date) -> CGImage {
        let odo = Odometer(digits: OdometerModel.lifetimeDigits)
        let from = odo.wheels(position: start), to = odo.wheels(position: end)
        let wheels = zip(from, to).map { Double($0) + Double($1 - $0) * progress }
        let shown = start + Int(Double(end - start) * progress)
        let renderer = ImageRenderer(content: PromoCard(wheels: wheels, gained: shown - start, since: since)
            .frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.cgImage!
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let buffer = out else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        context?.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Odometer wheels from explicit (fractional) positions, for frame-by-frame rendering.
struct WheelStrip: View {
    let wheels: [Double]
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: max(1, fontSize * 0.1)) {
            ForEach(Array(wheels.enumerated()), id: \.offset) { index, wheel in
                RollingDigit(position: wheel, fontSize: fontSize, inverted: index == wheels.count - 1)
            }
        }
        .padding(.horizontal, fontSize * 0.2)
        .padding(.vertical, fontSize * 0.12)
        .background(RoundedRectangle(cornerRadius: fontSize * 0.25).fill(Palette.bezel))
    }
}

struct PromoCard: View {
    let wheels: [Double]
    let gained: Int
    let since: Date

    var body: some View {
        ZStack(alignment: .top) {
            Palette.dash
            RadialGradient(colors: [Palette.accent.opacity(0.22), .clear], center: .center,
                           startRadius: 10, endRadius: 620)

            // A slice of the macOS menu bar, so it reads as a menu bar app at a glance.
            HStack(spacing: 22) {
                Spacer()
                WheelStrip(wheels: wheels, fontSize: 17)
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute())
            }
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 36)
            .frame(height: 52)
            .background(Color.white.opacity(0.07))

            VStack(spacing: 34) {
                Spacer()
                Text("~ token odometer")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.accent)
                WheelStrip(wheels: wheels, fontSize: 104)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                VStack(spacing: 12) {
                    Text("every token I've burned with Claude Code")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                    Text("+\(gained.formatted()) since \(since.formatted(.dateTime.hour().minute())) · live in my menu bar")
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.dim)
                }
                Spacer()
            }
            .padding(.top, 52)
        }
    }
}
