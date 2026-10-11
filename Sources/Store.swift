import AppKit
import Foundation
import Security

// MARK: - fan

struct FanSwitch: Identifiable {
    let field: String
    let label: String
    let icon: String
    let operableWhenOff: Bool
    var id: String { field }
}

struct AngleRange {
    let range: ClosedRange<Int>
    let step: Int
}

/// A fan as described by the cloud: capabilities come from the model's
/// `config`, live values from `state`.
final class Fan: Identifiable {
    let sn: String
    let name: String
    let model: String
    let speeds: ClosedRange<Int>?
    let modes: [String]
    let oscModes: [String]
    let horizontal: AngleRange?
    let vertical: AngleRange?
    let toggles: [FanSwitch]
    var state: JSON
    var version = 0  // bumped on every command so stale reads are dropped
    var id: String { sn }

    static let kinds: Set<String> = ["fan", "circulation_fan", "ceiling_fan", "rgblight_ceiling_fan"]

    init?(device: JSON) {
        let config = device["config"] as? JSON ?? [:]
        let fanConfig = config["fan_entity_config"] as? JSON ?? [:]
        let kind = device["deviceType"] as? String ?? ""
        guard let sn = device["deviceSn"] as? String, Fan.kinds.contains(kind) || !fanConfig.isEmpty else {
            return nil
        }
        self.sn = sn
        model = device["model"] as? String ?? ""
        name = device["deviceName"] as? String ?? (model.isEmpty ? String(localized: "Dreo Fan") : model)
        state = device["state"] as? JSON ?? [:]

        let range = (fanConfig["speed_range"] as? [Any])?.compactMap(int) ?? []
        speeds = range.count >= 2 && range[0] < range[1] ? range[0]...range[1] : nil
        modes = fanConfig["preset_modes"] as? [String] ?? []

        let selects = (config["select_entity_config"] as? JSON)?.values.compactMap { $0 as? JSON } ?? []
        let oscSelect = selects.first { $0["directive_name"] as? String == "oscmode" }
        oscModes = oscSelect?["options"] as? [String] ?? ["Fixed", "Horizontal", "Vertical", "Both"]

        func angle(_ key: String) -> AngleRange? {
            let conf = (fanConfig["fixed_angle"] as? JSON)?[key] as? JSON
            let bounds = (conf?["range"] as? [Any])?.compactMap(int) ?? []
            guard bounds.count == 2, bounds[0] < bounds[1] else { return nil }
            return AngleRange(range: bounds[0]...bounds[1], step: max(1, int(conf?["step"]) ?? 1))
        }
        horizontal = angle("horizontal")
        vertical = angle("vertical")

        let initial = state
        let configured = (config["toggle_entity_config"] as? JSON)?.values.compactMap { $0 as? JSON } ?? []
        var toggles = configured.compactMap { entry -> FanSwitch? in
            guard let field = entry["field"] as? String else { return nil }
            let known = Fan.knownToggles[field]
            return FanSwitch(
                field: field,
                label: known?.label ?? entry["labelName"] as? String ?? field,
                icon: known?.icon ?? "switch.2",
                operableWhenOff: bool(entry["operableWhenOff"]) ?? false
            )
        }
        if configured.isEmpty {  // no config: fall back to the known switches the fan reports
            toggles = Fan.knownToggles.keys.sorted().compactMap { field in
                guard initial[field] != nil, let known = Fan.knownToggles[field] else { return nil }
                return FanSwitch(field: field, label: known.label, icon: known.icon, operableWhenOff: true)
            }
        }
        self.toggles = toggles.sorted { $0.label < $1.label }
    }

    static var knownToggles: [String: (label: String, icon: String)] {
        [
            "childlock_switch": (String(localized: "Child lock"), "lock"),
            "mute_switch": (String(localized: "Mute beeps"), "speaker.slash"),
            "led_switch": (String(localized: "Display light"), "lightbulb"),
            "lightsensor_switch": (String(localized: "Light sensor"), "sun.max"),
        ]
    }

    var on: Bool { bool(state["power_switch"]) ?? false }
    var online: Bool { bool(state["connected"]) ?? true }
    var speed: Int? { int(state["speed"]) }
    var mode: String? { state["mode"] as? String }
    var oscillate: Bool? { bool(state["oscillate"]) }
    var oscMode: String? { state["oscmode"] as? String }

    var angle: (h: Int, v: Int) {
        let value = state["fixed_angle"] as? JSON
        return (int(value?["H"]) ?? 0, int(value?["V"]) ?? 0)
    }

    var summary: String {
        if !online { return String(localized: "Offline: check the fan's Wi-Fi") }
        if !on { return String(localized: "Off") }
        var parts = [String(localized: "On")]
        if let speed { parts.append(String(localized: "speed \(speed)")) }
        if let mode { parts.append(modeLabel(mode).lowercased()) }
        if (oscMode.map { $0 != "Fixed" } ?? false) || oscillate == true {
            parts.append(String(localized: "oscillating"))
        }
        return parts.joined(separator: " · ")
    }
}

func modeLabel(_ mode: String) -> String {
    switch mode.lowercased() {
    case "normal": String(localized: "Normal")
    case "natural": String(localized: "Natural")
    case "sleep": String(localized: "Sleep")
    case "auto": String(localized: "Auto")
    case "turbo": String(localized: "Turbo")
    case "custom": String(localized: "Custom")
    case "eco": String(localized: "Eco")
    case "manual": String(localized: "Manual")
    case "reverse": String(localized: "Reverse")
    default: mode.capitalized
    }
}

func modeIcon(_ mode: String) -> String {
    [
        "normal": "wind", "natural": "leaf", "sleep": "moon.zzz", "auto": "sparkles",
        "turbo": "bolt", "custom": "slider.horizontal.3", "eco": "leaf.circle",
        "manual": "hand.raised", "reverse": "arrow.uturn.backward",
    ][mode.lowercased()] ?? "circle"
}

func oscLabel(_ mode: String) -> String {
    switch mode.lowercased() {
    case "fixed": String(localized: "Fixed")
    case "horizontal": String(localized: "Horizontal")
    case "vertical": String(localized: "Vertical")
    case "both": String(localized: "Both")
    default: mode.capitalized
    }
}

// MARK: - app state

@MainActor
final class Store: ObservableObject {
    @Published private(set) var loggedIn = false
    @Published private(set) var connecting = false
    @Published private(set) var fans: [Fan] = []
    @Published private(set) var revision = 0
    @Published var message: String?
    @Published var loginError: String?

    nonisolated static let isDemo = CommandLine.arguments.contains("--demo")
        || ProcessInfo.processInfo.environment["BREEZE_DEMO"] == "1"
    /// Demo mode keeps its settings apart from the real ones.
    nonisolated static var defaults: UserDefaults {
        isDemo ? UserDefaults(suiteName: "io.github.rodartej.breeze-for-dreo.demo")! : .standard
    }

    private var api: DreoBackend?
    private var lastRefresh = Date.distantPast
    private var queue: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?
    private var inFlight = 0  // commands sent but not yet answered
    private var defaults: UserDefaults { Store.defaults }

    var email: String { defaults.string(forKey: "email") ?? "" }

    var fan: Fan? {
        let selected = defaults.string(forKey: "selected")
        return fans.first { $0.sn == selected } ?? fans.first
    }

    init() {
        if Store.isDemo {
            start(FakeDreo())
        } else if !email.isEmpty, let secret = Keychain.read(email) {
            start(DreoAPI(email: email, secret: secret))
        }
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.lastRefresh) > 3 else { return }
                await self.refresh()
            }
        }
    }

    // MARK: session

    private func start(_ api: DreoBackend) {
        self.api = api
        loggedIn = true
        Task { await connect() }
    }

    private func connect() async {
        guard let api else { return }
        connecting = true
        defer { connecting = false }
        do {
            try await api.login()
            setDevices(try await api.devices())
            message = nil
        } catch DreoError.badCredentials {
            logout()
            loginError = String(localized: "Your Dreo password changed. Please sign in again.")
        } catch {
            message = describe(error)
        }
    }

    func login(email: String, password: String) async {
        loginError = nil
        connecting = true
        defer { connecting = false }
        let secret = DreoAPI.hash(password)  // only this MD5 is stored, never the password
        let api = DreoAPI(email: email, secret: secret)
        do {
            try await api.login()
            let devices = try await api.devices()
            Keychain.save(secret, for: email)
            defaults.set(email, forKey: "email")
            self.api = api
            loggedIn = true
            message = nil
            setDevices(devices)
        } catch {
            loginError = describe(error)
        }
    }

    func logout() {
        if !Store.isDemo { Keychain.delete(email) }
        defaults.removeObject(forKey: "selected")
        api = nil
        fans = []
        loggedIn = false
        message = nil
    }

    private func setDevices(_ devices: [JSON]) {
        for device in devices {
            let data = try? JSONSerialization.data(withJSONObject: device, options: [.sortedKeys])
            log("device: \(data.flatMap { String(data: $0, encoding: .utf8) } ?? "?")")
        }
        fans = devices.compactMap(Fan.init)
        if fans.isEmpty { message = String(localized: "No fans found in your Dreo account") }
        Task { await refresh() }
    }

    func choose(_ fan: Fan) {
        defaults.set(fan.sn, forKey: "selected")
        changed()
        Task { await refresh() }
    }

    // MARK: reading

    func refresh() async {
        // Reading while commands are in flight would briefly undo them on screen.
        guard let api, !connecting, inFlight == 0 else { return }
        guard let fan else {
            if loggedIn, let devices = try? await api.devices() { setDevices(devices) }
            return
        }
        lastRefresh = Date()
        let version = fan.version
        do {
            let state = try await api.status(fan.sn)
            if fan.version == version, inFlight == 0 {
                fan.state.merge(state) { $1 }
                changed()
            }
            message = nil
        } catch {
            message = describe(error)
        }
    }

    // MARK: commands

    func send(_ desired: JSON, turnOn: Bool = true) {
        guard let api, let fan else { return }
        var desired = desired
        if turnOn, !fan.on, desired["power_switch"] == nil { desired["power_switch"] = true }
        fan.version += 1
        fan.state.merge(desired) { $1 }  // the UI reacts right away
        message = nil
        changed()
        let command = desired
        inFlight += 1
        enqueue {
            do {
                try await api.control(fan.sn, command)
            } catch {
                self.message = describe(error)
                fan.version += 1
            }
            self.inFlight -= 1
            self.refreshSoon()
        }
    }

    func togglePower() {
        guard let fan else { return }
        send(["power_switch": !fan.on])
    }

    func step(_ delta: Int) {
        guard let fan, let speeds = fan.speeds else { return }
        let next = min(speeds.upperBound, max(speeds.lowerBound, (fan.speed ?? speeds.lowerBound) + delta))
        send(["speed": next])
    }

    /// Commands go out one at a time, in the order they were given.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }

    /// Confirms with the cloud shortly after the last command.
    private func refreshSoon() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func changed() { revision += 1 }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "Breeze for Dreo"

    private static func query(_ account: String) -> JSON {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ secret: String, for account: String) {
        delete(account)
        var item = query(account)
        item[kSecValueData as String] = Data(secret.utf8)
        item[kSecAttrLabel as String] = service
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { log("keychain: save failed (\(status))") }
    }

    static func read(_ account: String) -> String? {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
