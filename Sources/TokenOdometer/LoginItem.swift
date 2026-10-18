import ServiceManagement

/// Scriptable twin of the popover's "Launch at login" switch, so it can be set without clicking.
enum LoginItem {
    static func handle(_ command: String) {
        let service = SMAppService.mainApp
        do {
            switch command {
            case "on": try service.register()
            case "off": try service.unregister()
            default: break
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }
        print("launch at login: \(describe(service.status))")
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires approval in System Settings > General > Login Items"
        case .notRegistered: return "not registered"
        case .notFound: return "not found (run it from a built TokenOdometer.app)"
        @unknown default: return "unknown"
        }
    }
}
