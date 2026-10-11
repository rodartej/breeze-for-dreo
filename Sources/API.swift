import CryptoKit
import Foundation

typealias JSON = [String: Any]

enum DreoError: LocalizedError {
    case badCredentials
    case expired
    case rateLimited
    case server(String)
    case network

    var errorDescription: String? {
        switch self {
        case .badCredentials: String(localized: "Wrong email or password")
        case .expired: String(localized: "Your Dreo session expired")
        case .rateLimited: String(localized: "Too many requests; wait a moment")
        case .server(let message): String(localized: "Dreo said: \(message)")
        case .network: String(localized: "Can't reach Dreo")
        }
    }
}

func describe(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(localized: "Something went wrong talking to Dreo")
}

/// What the app needs from the cloud. `FakeDreo` mimics it for demo mode.
protocol DreoBackend: AnyObject {
    func login() async throws
    func devices() async throws -> [JSON]
    func status(_ sn: String) async throws -> JSON
    func control(_ sn: String, _ desired: JSON) async throws
}

/// Dreo's official open API, the same one their Home Assistant integration uses.
/// The client ID and secret are the public ones shipped in Dreo's open-source
/// libraries (pydreo-cloud, hass-dreoverse).
actor DreoAPI: DreoBackend {
    private static let clientID = "89ef537b2202481aaaf9077068bcb0c9"
    private static let clientSecret = "41b20a1f60e9499e89c8646c31f93ea1"
    private static let usURL = "https://open-api-us.dreo-tech.com"
    private static let euURL = "https://open-api-eu.dreo-tech.com"

    let email: String
    private let secret: String  // MD5 of the password, as the API expects
    private var token: String?
    private var endpoint = DreoAPI.usURL

    init(email: String, secret: String) {
        self.email = email
        self.secret = secret
    }

    nonisolated static func hash(_ password: String) -> String {
        Insecure.MD5.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func login() async throws {
        let body: JSON = [
            "client_id": Self.clientID,
            "client_secret": Self.clientSecret,
            "grant_type": "openapi",
            "scope": "all",
            "email": email,
            "password": secret,
        ]
        let data: Any?
        do {
            data = try await request(Self.usURL + "/api/oauth/login", method: "POST", body: body)
        } catch DreoError.server, DreoError.expired {
            throw DreoError.badCredentials
        }
        guard let raw = (data as? JSON)?["access_token"] as? String else {
            throw DreoError.server("no access token")
        }
        // The token ends with its region: "abc:EU".
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        token = parts[0]
        endpoint = parts.count == 2 && parts[1].uppercased() == "EU" ? Self.euURL : Self.usURL
    }

    func devices() async throws -> [JSON] {
        let data = try await authed("/api/device/list")
        if let list = data as? [JSON] { return list }
        let wrapped = data as? JSON
        return (wrapped?["list"] ?? wrapped?["devices"]) as? [JSON] ?? []
    }

    func status(_ sn: String) async throws -> JSON {
        try await authed("/api/device/state", query: ["deviceSn": sn]) as? JSON ?? [:]
    }

    func control(_ sn: String, _ desired: JSON) async throws {
        log("control \(sn): \(desired)")
        _ = try await authed("/api/device/control", method: "POST", body: ["devicesn": sn, "desired": desired])
    }

    /// Calls with the token, logging in again once if it expired.
    private func authed(_ path: String, method: String = "GET", query: [String: String] = [:], body: JSON? = nil) async throws -> Any? {
        if token == nil { try await login() }
        do {
            return try await request(endpoint + path, method: method, query: query, body: body)
        } catch DreoError.expired {
            try await login()
            return try await request(endpoint + path, method: method, query: query, body: body)
        }
    }

    private func request(_ url: String, method: String, query: [String: String] = [:], body: JSON? = nil) async throws -> Any? {
        var components = URLComponents(string: url)!
        let params = query.merging([
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000)),
            "pydreover": "1.0.0",
        ]) { mine, _ in mine }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("openapi/1.0.0", forHTTPHeaderField: "UA")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log("network: \(error.localizedDescription)")
            throw DreoError.network
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: throw DreoError.expired
        case 429: throw DreoError.rateLimited
        case let code: throw DreoError.server("HTTP \(code)")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? JSON else {
            throw DreoError.server("invalid response")
        }
        if let code = json["code"] as? Int, code != 0 {
            let message = json["msg"] as? String ?? "code \(code)"
            log("Dreo \(code): \(message)")
            if message.lowercased().contains("token") { throw DreoError.expired }
            throw DreoError.server(message)
        }
        return json["data"]
    }
}

/// Two fake fans to try the app without an account: `Breeze --demo`.
actor FakeDreo: DreoBackend {
    private var devicesData: [JSON] = [
        [
            "deviceSn": "DEMO-CIRC",
            "deviceName": "Living Room Circulator",
            "model": "DR-HPF007S",
            "deviceType": "circulation_fan",
            "config": [
                "fan_entity_config": [
                    "preset_modes": ["Normal", "Natural", "Sleep", "Auto", "Turbo", "Custom"],
                    "speed_range": [1, 9],
                    "fixed_angle": [
                        "mode": "pair",
                        "horizontal": ["range": [-75, 75], "step": 5],
                        "vertical": ["range": [-30, 90], "step": 5],
                    ],
                    "oscrange": [
                        "mode": "all", "horizontal_spacing": 30, "vertical_spacing": 30,
                        "left": ["range": [-75, 45], "step": 5],
                        "right": ["range": [-45, 75], "step": 5],
                        "up": ["range": [0, 90], "step": 5],
                        "down": ["range": [-30, 60], "step": 5],
                    ],
                ],
                // Same shapes the real DR-HPF007S sends.
                "select_entity_config": [
                    ["selector": "DreoGenericModeSelect", "selector_mappings": [
                        "attr_name": "Display", "directive_name": "lightmode", "options": ["Auto", "On", "Off"],
                    ]],
                    ["selector": "DreoGenericModeSelect", "selector_mappings": [
                        "attr_name": "oscillation direction", "directive_name": "oscmode",
                        "options": ["Fixed", "Horizontal", "Vertical", "Both", "SmartFollow"],
                    ]],
                    ["selector": "DreoGenericModeSelect", "selector_mappings": [
                        "attr_name": "Hor Follow Angle", "directive_name": "hwfpangle",
                        "options": ["30", "40", "50", "60", "70", "80", "90", "100"],
                    ]],
                ],
                "toggle_entity_config": [
                    "childlock": ["field": "childlock_switch", "labelName": "Child lock", "operableWhenOff": true],
                    "mute": ["field": "mute_switch", "labelName": "Panel Sound"],
                ],
            ],
            "state": [
                "connected": true, "power_switch": true, "speed": 4, "mode": "Natural",
                "oscmode": "Fixed", "fixed_angle": ["V": "0", "H": "15"],
                "oscrange": ["L": "-45", "R": "45", "U": "90", "D": "-30"],
                "hwfpangle": "60", "lightmode": "Auto",
                "childlock_switch": false, "mute_switch": false,
            ],
        ],
        [
            "deviceSn": "DEMO-TORRE",
            "deviceName": "Bedroom Tower Fan",
            "model": "DR-HTF008S",
            "deviceType": "fan",
            "config": ["fan_entity_config": ["speed_range": [1, 5], "preset_modes": ["Sleep", "Auto", "Natural", "Normal"]]],
            "state": ["connected": true, "power_switch": false, "speed": 2, "mode": "Normal", "oscillate": true],
        ],
    ]

    private func index(_ sn: String) -> Int { devicesData.firstIndex { $0["deviceSn"] as? String == sn }! }

    func login() async throws { try await Task.sleep(for: .milliseconds(300)) }

    func devices() async throws -> [JSON] {
        try await Task.sleep(for: .milliseconds(300))
        return devicesData
    }

    func status(_ sn: String) async throws -> JSON {
        try await Task.sleep(for: .milliseconds(200))
        return devicesData[index(sn)]["state"] as? JSON ?? [:]
    }

    /// Seconds before a change shows up in `status`, like the real cloud (BREEZE_DEMO_LAG).
    private let lag = Double(ProcessInfo.processInfo.environment["BREEZE_DEMO_LAG"] ?? "") ?? 0

    func control(_ sn: String, _ desired: JSON) async throws {
        try await Task.sleep(for: .milliseconds(300))
        log("demo \(sn): \(desired)")
        guard lag > 0 else { return apply(sn, desired) }
        Task {
            try? await Task.sleep(for: .seconds(lag))
            apply(sn, desired)
        }
    }

    private func apply(_ sn: String, _ desired: JSON) {
        let i = index(sn)
        var state = devicesData[i]["state"] as? JSON ?? [:]
        state.merge(desired) { $1 }
        devicesData[i]["state"] = state
    }
}

// MARK: - helpers

func int(_ value: Any?) -> Int? {
    switch value {
    case let n as NSNumber: n.intValue
    case let s as String: Int(s)
    default: nil
    }
}

func bool(_ value: Any?) -> Bool? {
    switch value {
    case let n as NSNumber: n.boolValue
    case let s as String: ["1", "true", "on"].contains(s.lowercased())
    default: nil
    }
}

private let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Breeze for Dreo.log")

func log(_ message: String) {
    let line = "\(Date().formatted(.iso8601)) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: logURL)
    }
}
