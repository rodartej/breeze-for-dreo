import ServiceManagement
import SwiftUI

/// Icon in the menu bar: the fan, plus the speed while it runs.
struct MenuBarLabel: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let _ = store.revision
        let fan = store.fan
        let icon = fan.map { !$0.online ? "fan.slash" : ($0.on ? "fan.fill" : "fan") } ?? "fan"
        if let fan, fan.on, fan.online, let speed = fan.speed {
            Image(nsImage: Self.render(icon: icon, text: "\(speed)"))
        } else {
            Image(systemName: icon)
        }
    }

    /// The menu bar only shows one image or text, so icon and speed are drawn together.
    private static func render(icon: String, text: String) -> NSImage {
        let content = HStack(spacing: 3) {
            Image(systemName: icon)
            Text(verbatim: text).monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true  // tinted like every other menu bar icon
        return image
    }
}

/// Compact controls shown when you click the menu bar icon.
struct MenuBarPanel: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let _ = store.revision
        VStack(spacing: 12) {
            if store.loggedIn, let fan = store.fan {
                HStack(spacing: 12) {
                    PowerButton(fan: fan, size: 46) { store.togglePower() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fan.name).font(.headline).lineLimit(1)
                        Text(fan.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                if let message = store.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                FanControls(fan: fan, compact: true).id(fan.sn)
            } else {
                Group {
                    if store.loggedIn {
                        Text("Looking for your fans…")
                    } else {
                        Text("Open Breeze to sign in.")
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
            }
            HStack {
                Button("Open Breeze", action: showWindow)
                Spacer()
                Button(action: showSettings) { Image(systemName: "gearshape") }
                    .help(Text("Settings…"))
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help(Text("Quit Breeze"))
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 320)
    }

    private func showWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate()
    }

    private func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openSettings()
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("showInMenuBar", store: Store.defaults) private var showInMenuBar = false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Text("Keeps Breeze in the menu bar so you can control your fan without the window. Closing the window leaves it running there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Account") {
                if store.loggedIn {
                    LabeledContent("Signed in as") {
                        Text(verbatim: Store.isDemo ? "demo" : store.email)
                    }
                    Button("Sign Out") { store.logout() }
                } else {
                    Text("Not signed in").foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Unofficial app, not affiliated with Dreo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/rodartej/breeze-for-dreo")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = String(localized: "Couldn't change the login item: \(error.localizedDescription)")
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}
