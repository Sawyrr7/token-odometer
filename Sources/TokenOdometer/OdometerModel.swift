import Foundation
import Observation
import ServiceManagement
@preconcurrency import OdometerCore

@MainActor @Observable
final class OdometerModel {
    private(set) var today = TokenCounts.zero
    private(set) var todayByModel: [ModelFamily: TokenCounts] = [:]
    private(set) var trip = TokenCounts.zero
    private(set) var lifetime: Int
    private(set) var tripStart: Date
    private(set) var speed: Double = 0
    private(set) var loaded = false
    private(set) var odometer: Odometer

    var includeCacheReads: Bool {
        didSet {
            UserDefaults.standard.set(includeCacheReads, forKey: Keys.cacheReads)
            odometer = Odometer(digits: Self.digits(includeCacheReads))
            refreshSpeed()
        }
    }

    /// Mirrors System Settings > General > Login Items, which the user can also change there.
    var opensAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard opensAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            LoginItem.handle(opensAtLogin ? "on" : "off")
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    var todayTotal: Int { today.total(includingCacheReads: includeCacheReads) }
    var tripTotal: Int { trip.total(includingCacheReads: includeCacheReads) }
    var position: Int { odometer.position(total: todayTotal) }

    @ObservationIgnored private let scanner: TranscriptScanner
    @ObservationIgnored private let queue = DispatchQueue(label: "token-odometer.scanner", qos: .utility)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var polling = false

    private enum Keys {
        static let cacheReads = "includeCacheReads"
        static let tripStart = "tripStart"
        static let lifetimeBase = "lifetimeBase"
        static let lifetimeAnchor = "lifetimeAnchor"
    }

    static let startingLifetime = 0
    static let lifetimeDigits = 10

    /// Starts the permanent reading over from `value`. Used by `--lifetime N` while the app is quit.
    static func storeLifetime(_ value: Int, at now: Date = Date()) {
        UserDefaults.standard.set(value, forKey: Keys.lifetimeBase)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Keys.lifetimeAnchor)
    }

    init(root: URL = TranscriptScanner.defaultRoot, now: Date = Date()) {
        let defaults = UserDefaults.standard
        let cacheReads = defaults.bool(forKey: Keys.cacheReads)
        let storedTrip = defaults.object(forKey: Keys.tripStart) as? Double
        let tripStart = storedTrip.map(Date.init(timeIntervalSince1970:)) ?? now
        if storedTrip == nil { defaults.set(now.timeIntervalSince1970, forKey: Keys.tripStart) }
        if defaults.object(forKey: Keys.lifetimeBase) == nil { Self.storeLifetime(Self.startingLifetime, at: now) }
        let lifetimeBase = defaults.integer(forKey: Keys.lifetimeBase)
        let lifetimeAnchor = Date(timeIntervalSince1970: defaults.double(forKey: Keys.lifetimeAnchor))

        self.includeCacheReads = cacheReads
        self.tripStart = tripStart
        self.lifetime = lifetimeBase
        self.odometer = Odometer(digits: Self.digits(cacheReads))
        self.scanner = TranscriptScanner(
            root: root, now: now, tripStart: tripStart, lifetimeBase: lifetimeBase, lifetimeAnchor: lifetimeAnchor)
    }

    static func digits(_ includeCacheReads: Bool) -> Int { includeCacheReads ? 10 : 8 }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// Blocking read for snapshot mode.
    func pollNow() {
        _ = queue.sync { scanner.poll(now: Date()) }
        publish(rolled: false)
    }

    func resetTrip() {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Keys.tripStart)
        queue.async { [scanner] in scanner.resetTrip(at: now) }
        tripStart = now
        trip = .zero
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        queue.async { [scanner] in
            let rolled = scanner.poll(now: Date())
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.polling = false
                    self.publish(rolled: rolled)
                }
            }
        }
    }

    private func publish(rolled: Bool) {
        if rolled { odometer.rollOver(from: todayTotal) }
        let tally = queue.sync { scanner.tally }
        today = tally.today
        todayByModel = tally.todayByModel
        trip = tally.trip
        tripStart = tally.tripStart
        lifetime = tally.lifetime
        if rolled { Self.storeLifetime(tally.lifetimeBase, at: tally.lifetimeAnchor) }
        loaded = true
        refreshSpeed()
    }

    private func refreshSpeed() {
        let cacheReads = includeCacheReads
        speed = queue.sync { scanner.speed(now: Date(), includingCacheReads: cacheReads) }
    }
}
