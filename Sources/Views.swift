import SwiftUI

let brandGradient = LinearGradient(
    colors: [Color(red: 0.20, green: 0.78, blue: 0.95), Color(red: 0.10, green: 0.36, blue: 0.90)],
    startPoint: .top, endPoint: .bottom
)

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if !store.loggedIn {
                LoginView()
            } else if let fan = store.fan {
                ControlView(fan: fan).id(fan.sn)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    if let message = store.message {
                        Text(message).foregroundStyle(.secondary)
                    } else {
                        Text("Looking for your fans…").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
        .frame(width: 380)
        .onAppear { NSApp.setActivationPolicy(.regular) }  // back in the Dock if it was menu-bar only
    }
}

// MARK: - sign in

struct LoginView: View {
    @EnvironmentObject var store: Store
    @State private var email = ""
    @State private var password = ""
    @State private var showGoogle = false
    @FocusState private var focus: Field?

    enum Field { case email, password }

    var body: some View {
        VStack(spacing: 14) {
            AppBadge(size: 72).padding(.top, 6)
            VStack(spacing: 4) {
                Text("Breeze").font(.largeTitle.bold())
                Text("Sign in with your Dreo app account").foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)

            if let error = store.loginError {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            Button(action: submit) {
                ZStack {
                    Text("Sign In").opacity(store.connecting ? 0 : 1)
                    if store.connecting { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(email.isEmpty || password.isEmpty || store.connecting)

            Button { showGoogle = true } label: {
                Label("I use Google to sign in", systemImage: "g.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Unofficial app, not affiliated with Dreo. Your login is stored in your Mac's Keychain.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .onAppear {
            email = store.email
            focus = email.isEmpty ? .email : .password
        }
        .sheet(isPresented: $showGoogle) { GoogleHelpView() }
    }

    private func submit() {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, !password.isEmpty, !store.connecting else { return }
        Task { await store.login(email: email, password: password) }
    }
}

struct GoogleHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let steps: [LocalizedStringKey] = [
        "Open the Dreo app on your phone and go to Profile",
        "Tap your name at the top",
        "Open Account Security",
        "Tap Change Login Password",
        "Enter the code sent to your email, choose a password and tap Finish",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Create a password for your Google account", systemImage: "key.fill")
                .font(.headline)
            Text("Dreo only lets other apps sign in with an email and password. Your Google account can have one, and you can keep using Google on your phone.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.accentColor))
                        Text(step).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("Then sign in here with that email and password.").font(.callout)
            HStack {
                Link("Open Dreo's guide", destination: URL(string: "https://support.dreo.com/cs/article/create-password-in-app")!)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 340)
    }
}

// MARK: - controls

struct ControlView: View {
    @EnvironmentObject var store: Store
    let fan: Fan

    var body: some View {
        let _ = store.revision  // redraw on every state change
        VStack(spacing: 14) {
            header
            PowerButton(fan: fan, size: 128) { store.togglePower() }
                .padding(.top, 2)
            Text(fan.summary).font(.callout).foregroundStyle(.secondary)
            if let message = store.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            FanControls(fan: fan)
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 18)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(fan.name).font(.title3.weight(.semibold)).lineLimit(1)
                Text(fan.model).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            FanMenu(fan: fan)
        }
    }
}

/// The cards shared by the window and the menu bar panel.
struct FanControls: View {
    @EnvironmentObject var store: Store
    let fan: Fan
    var compact = false

    var body: some View {
        VStack(spacing: 10) {
            if let speeds = fan.speeds {
                SpeedCard(speed: fan.speed, range: speeds, on: fan.on)
            }
            if !fan.modes.isEmpty { ModeCard(fan: fan) }
            if fan.oscMode != nil || fan.oscillate != nil { OscillationCard(fan: fan, showAngles: !compact) }
            if !compact, !fan.toggles.isEmpty { SwitchesCard(fan: fan) }
        }
        .disabled(!fan.online)
    }
}

struct FanMenu: View {
    @EnvironmentObject var store: Store
    let fan: Fan

    var body: some View {
        Menu {
            if store.fans.count > 1 {
                Section("Fan") {
                    ForEach(store.fans) { other in
                        Button {
                            store.choose(other)
                        } label: {
                            if other.sn == fan.sn {
                                Label(other.name, systemImage: "checkmark")
                            } else {
                                Text(other.name)
                            }
                        }
                    }
                }
            }
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
            SettingsLink { Label("Settings…", systemImage: "gearshape") }
            Divider()
            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") { store.logout() }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct AppBadge: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(brandGradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: "fan.fill").font(.system(size: size * 0.5)).foregroundStyle(.white))
            .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
    }
}

struct PowerButton: View {
    let fan: Fan
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fan.on ? AnyShapeStyle(brandGradient) : AnyShapeStyle(.quaternary))
                    .shadow(color: fan.on ? .blue.opacity(0.45) : .clear, radius: size / 7, y: size / 20)
                SpinningFan(spinning: fan.on, speed: fan.speed ?? 0, maxSpeed: fan.speeds?.upperBound ?? 1)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(fan.on ? Color.white : Color.secondary)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.spring(duration: 0.25), value: hovering)
            .animation(.easeInOut(duration: 0.3), value: fan.on)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(!fan.online)
        .help(fan.on ? Text("Turn off") : Text("Turn on"))
        .accessibilityLabel(fan.on ? Text("Turn fan off") : Text("Turn fan on"))
    }
}

/// Spins faster at higher speeds, without jumping when the speed changes.
struct SpinningFan: View {
    let spinning: Bool
    let speed: Int
    let maxSpeed: Int
    @State private var offset = 0.0

    private func rate(_ speed: Int) -> Double {
        90 + Double(speed) / Double(max(maxSpeed, 1)) * 810  // degrees per second
    }

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Image(systemName: spinning ? "fan.fill" : "fan")
                .rotationEffect(.degrees((rate(speed) * t + offset).truncatingRemainder(dividingBy: 360)))
        }
        .onChange(of: speed) { old, new in
            offset += (rate(old) - rate(new)) * Date().timeIntervalSinceReferenceDate
        }
    }
}

struct Card<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing {
                    Text(trailing).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SpeedCard: View {
    @EnvironmentObject var store: Store
    let speed: Int?
    let range: ClosedRange<Int>
    let on: Bool
    @State private var draft = 1.0
    @State private var pending: Task<Void, Never>?

    var body: some View {
        Card(title: "Speed", icon: "gauge.with.dots.needle.50percent",
             trailing: String(localized: "\(Int(draft)) of \(range.upperBound)")) {
            HStack(spacing: 10) {
                stepButton("minus", -1)
                Slider(
                    value: Binding(get: { draft }, set: { draft = $0; commitSoon() }),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                stepButton("plus", 1)
            }
        }
        .onAppear { draft = Double(speed ?? range.lowerBound) }
        .onChange(of: speed) { _, new in
            if pending == nil, let new { draft = Double(new) }
        }
    }

    private func stepButton(_ icon: String, _ delta: Double) -> some View {
        Button {
            draft = min(Double(range.upperBound), max(Double(range.lowerBound), draft + delta))
            commitSoon()
        } label: {
            Image(systemName: icon).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    /// Waits until you let go so only the final value is sent.
    private func commitSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            pending = nil
            let value = Int(draft)
            if value != speed || !on { store.send(["speed": value]) }
        }
    }
}

struct ModeCard: View {
    @EnvironmentObject var store: Store
    let fan: Fan

    var body: some View {
        Card(title: "Mode", icon: "dial.medium") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(fan.modes, id: \.self) { mode in
                    let selected = mode.lowercased() == fan.mode?.lowercased()
                    Button { store.send(["mode": mode]) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: modeIcon(mode)).font(.system(size: 17)).frame(height: 22)
                            Text(modeLabel(mode)).font(.caption).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(
                            selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct OscillationCard: View {
    @EnvironmentObject var store: Store
    let fan: Fan
    var showAngles = true

    var body: some View {
        Card(title: "Oscillation", icon: "fan.oscillation") {
            if let current = fan.oscMode {
                Picker("Oscillation", selection: Binding(get: { current }, set: { store.send(["oscmode": $0]) })) {
                    ForEach(fan.oscModes, id: \.self) { Text(oscLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if showAngles, current.lowercased() == "fixed", fan.on, fan.horizontal != nil || fan.vertical != nil {
                    AngleSliders(fan: fan)
                }
            } else if let oscillate = fan.oscillate {
                HStack {
                    Text("Oscillate")
                    Spacer()
                    Toggle("Oscillate", isOn: Binding(get: { oscillate }, set: { store.send(["oscillate": $0]) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }
}

struct AngleSliders: View {
    @EnvironmentObject var store: Store
    let fan: Fan
    @State private var horizontal = 0.0
    @State private var vertical = 0.0
    @State private var pending: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 6) {
            if let range = fan.horizontal { row("Horizontal angle", "arrow.left.and.right", $horizontal, range) }
            if let range = fan.vertical { row("Vertical angle", "arrow.up.and.down", $vertical, range) }
        }
        .padding(.top, 4)
        .onAppear(perform: sync)
        .onChange(of: store.revision) { if pending == nil { sync() } }
    }

    private func sync() {
        horizontal = Double(fan.angle.h)
        vertical = Double(fan.angle.v)
    }

    private func row(_ title: LocalizedStringKey, _ icon: String, _ value: Binding<Double>, _ range: AngleRange) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; commitSoon() }),
                in: Double(range.range.lowerBound)...Double(range.range.upperBound),
                step: Double(range.step)
            )
            Text(verbatim: "\(Int(value.wrappedValue))°")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }

    private func commitSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            pending = nil
            store.send(["fixed_angle": ["H": Int(horizontal), "V": Int(vertical)]])
        }
    }
}

struct SwitchesCard: View {
    @EnvironmentObject var store: Store
    let fan: Fan

    var body: some View {
        Card(title: "Options", icon: "switch.2") {
            ForEach(fan.toggles) { item in
                HStack {
                    Label(item.label, systemImage: item.icon)
                    Spacer()
                    Toggle(item.label, isOn: Binding(
                        get: { bool(fan.state[item.field]) ?? false },
                        set: { store.send([item.field: $0], turnOn: false) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .disabled(!item.operableWhenOff && !fan.on)
            }
        }
    }
}
