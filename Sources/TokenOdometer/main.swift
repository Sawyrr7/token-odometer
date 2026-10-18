import AppKit
import SwiftUI

/// Lets clicks fall through the SwiftUI odometer to the status item's button.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = OdometerModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let host = PassthroughHostingView(rootView: MenuBarOdometer(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            button.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: 2),
        ])
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "Token Odometer"

        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        model.start()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@MainActor
func renderSnapshots(to dir: URL) {
    let model = OdometerModel()
    let started = Date()
    model.pollNow()
    print("scan took \(String(format: "%.1f", Date().timeIntervalSince(started)))s, today = \(model.todayTotal)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let shots: [(String, AnyView)] = [
        ("menubar.png", AnyView(MenuBarOdometer(model: model).padding(4).background(Color(white: 0.85)))),
        ("popover.png", AnyView(PopoverView(model: model))),
    ]
    for (name, view) in shots {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { print("failed to render \(name)"); continue }
        try? png.write(to: dir.appendingPathComponent(name))
        print("wrote \(dir.appendingPathComponent(name).path)")
    }
}

let args = CommandLine.arguments
if let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count {
    MainActor.assumeIsolated { renderSnapshots(to: URL(fileURLWithPath: args[flag + 1])) }
    exit(0)
}
if let flag = args.firstIndex(of: "--promo"), flag + 1 < args.count {
    MainActor.assumeIsolated {
        let model = OdometerModel()
        model.pollNow()
        let defaults = UserDefaults.standard
        let since = Date(timeIntervalSince1970: defaults.double(forKey: "lifetimeAnchor"))
        do {
            try PromoRenderer.render(start: defaults.integer(forKey: "lifetimeBase"), end: model.lifetime,
                                     since: since, to: URL(fileURLWithPath: args[flag + 1]))
        } catch { print("error: \(error)") }
    }
    exit(0)
}
if let flag = args.firstIndex(of: "--lifetime"), flag + 1 < args.count, let value = Int(args[flag + 1]) {
    MainActor.assumeIsolated { OdometerModel.storeLifetime(value) }
    print("lifetime set to \(value.formatted()) (quit and reopen the app to load it)")
    exit(0)
}
if let flag = args.firstIndex(of: "--login"), flag + 1 < args.count {
    LoginItem.handle(args[flag + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
