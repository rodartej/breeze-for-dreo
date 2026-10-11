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
        .background(KeepTopEdge())  // grow and shrink downward; the top edge stays put
        .onAppear { NSApp.setActivationPolicy(.regular) }  // back in the Dock if it was menu-bar only
    }
}

/// Keeps the window's top edge in place when its content changes height, so it grows
/// and shrinks downward like a normal Mac window. (SwiftUI's `windowResizeAnchor` does
/// this on macOS 26; this also works on macOS 15.)
struct KeepTopEdge: NSViewRepresentable {
    func makeNSView(context: Context) -> TopEdgeView { TopEdgeView() }
    func updateNSView(_ view: TopEdgeView, context: Context) {}

    final class TopEdgeView: NSView {
        private var top: CGFloat?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            top = window.frame.maxY
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restoreTop() }
            })
            observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.top = self?.window?.frame.maxY }
            })
        }

        private func restoreTop() {
            guard let window, let top, abs(window.frame.maxY - top) > 0.5 else { return }
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }
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
            StatusLine(fan: fan)
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

/// The fan's state, or the last error, always on one line so nothing below it moves.
struct StatusLine: View {
    @EnvironmentObject var store: Store
    let fan: Fan
    var font: Font = .callout

    var body: some View {
        ZStack {
            if let message = store.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            } else {
                Text(fan.summary)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .transition(.opacity)
            }
        }
        .font(font)
        .lineLimit(1)
        .truncationMode(.tail)
        .animation(.easeInOut(duration: 0.2), value: store.message)
        .animation(.easeInOut(duration: 0.2), value: fan.summary)
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
            if fan.oscMode != nil || fan.oscillate != nil { OscillationCard(fan: fan, showAim: !compact) }
            if !compact, !fan.toggles.isEmpty || !fan.selects.isEmpty { SwitchesCard(fan: fan) }
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
            .animation(.snappy(duration: 0.2), value: fan.mode)
        }
    }
}

struct OscillationCard: View {
    @EnvironmentObject var store: Store
    let fan: Fan
    var showAim = true

    var body: some View {
        Card(title: "Oscillation", icon: "fan.oscillation") {
            if let current = fan.oscMode {
                HStack(spacing: 6) {
                    ForEach(fan.oscModes, id: \.self) { option in
                        let selected = option.lowercased() == current.lowercased()
                        Button { store.send(["oscmode": option]) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: oscIcon(option)).font(.system(size: 14)).frame(height: 18)
                                Text(oscLabel(option)).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .animation(.snappy(duration: 0.2), value: current)
                if showAim, fan.horizontal != nil || fan.vertical != nil || fan.sweep != nil {
                    DirectionPad(fan: fan, mode: current)
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

/// Shows and sets where the fan points. In Fixed mode you drag the dot to aim it.
/// While oscillating, the shaded area is what it sweeps, and you drag an edge to change it.
/// Left/right is the horizontal angle, up/down the vertical one.
struct DirectionPad: View {
    @EnvironmentObject var store: Store
    let fan: Fan
    let mode: String
    @State private var h = 0
    @State private var v = 0
    @State private var sweep = (left: -45, right: 45, up: 45, down: -15)
    @State private var edge: Edge?
    @State private var dragging = false
    @State private var pending: Task<Void, Never>?

    private enum Edge { case left, right, up, down }
    private static let inset: CGFloat = 13

    @State private var follow = 60
    @FocusState private var focused: Bool  // after a click, the arrow keys move the dot

    private var fixed: Bool { mode.lowercased() == "fixed" }
    private var following: Bool { mode.lowercased() == "smartfollow" }
    private var sweepsH: Bool { ["horizontal", "both"].contains(mode.lowercased()) }
    private var sweepsV: Bool { ["vertical", "both"].contains(mode.lowercased()) }

    /// The pad covers every angle the fan can reach, aimed or sweeping.
    private var hSpan: ClosedRange<Int> { span(fan.horizontal?.range, fan.sweep?.left?.range, fan.sweep?.right?.range) }
    private var vSpan: ClosedRange<Int> { span(fan.vertical?.range, fan.sweep?.down?.range, fan.sweep?.up?.range) }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary)
                    crosshair(in: size)
                    if fixed { aimDot(in: size) } else { sweepArea(in: size) }
                }
                .contentShape(Rectangle())
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .opacity(focused && fixed ? 0.9 : 0)
                        .animation(.easeOut(duration: 0.15), value: focused)
                )
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
                    guard fixed else { return .ignored }
                    let steps = press.modifiers.contains(.shift) ? 3 : 1  // Shift moves faster
                    switch press.key {
                    case .leftArrow: step(h: -steps)
                    case .rightArrow: step(h: steps)
                    case .upArrow: step(v: steps)
                    default: step(v: -steps)
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    focused = false
                    return .handled
                }
                .gesture(drag(in: size))
                .accessibilityElement()
                .accessibilityLabel(Text("Fan direction"))
                .accessibilityValue(Text(verbatim: readoutText))
            }
            .frame(height: 104)

            readout
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 20)

            Group {
                if fixed {
                    Text("Drag the dot, or click and use the arrow keys")
                } else if following {
                    Text("Drag an edge to change how wide it follows you")
                } else {
                    Text("Drag an edge to change how far it sweeps")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
        .onAppear(perform: sync)
        .onChange(of: store.revision) { if !dragging, pending == nil { sync() } }
        .onChange(of: mode) { sync() }
    }

    // MARK: drawing

    private func crosshair(in size: CGSize) -> some View {
        let center = point(h: 0, v: 0, in: size)
        return Path { path in
            path.move(to: CGPoint(x: center.x, y: 6))
            path.addLine(to: CGPoint(x: center.x, y: size.height - 6))
            path.move(to: CGPoint(x: 6, y: center.y))
            path.addLine(to: CGPoint(x: size.width - 6, y: center.y))
        }
        .stroke(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
    }

    private func aimDot(in size: CGSize) -> some View {
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .scaleEffect(dragging ? 1.2 : 1)
            .position(point(h: h, v: v, in: size))
            .animation(dragging ? nil : .snappy(duration: 0.25), value: h)
            .animation(dragging ? nil : .snappy(duration: 0.25), value: v)
            .animation(.snappy(duration: 0.15), value: dragging)
    }

    @ViewBuilder
    private func sweepArea(in size: CGSize) -> some View {
        let rect = sweepRect(in: size)
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(0.22))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(dragging ? nil : .snappy(duration: 0.25), value: rect)
        if sweepsH || following {
            handle(width: 5, height: 24).position(x: rect.minX, y: rect.midY)
            handle(width: 5, height: 24).position(x: rect.maxX, y: rect.midY)
        }
        if sweepsV {
            handle(width: 24, height: 5).position(x: rect.midX, y: rect.minY)
            handle(width: 24, height: 5).position(x: rect.midX, y: rect.maxY)
        }
        if fan.on {  // a dot going back and forth, like the fan
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .position(
                        x: sweepsH || following ? rect.midX + CGFloat(sin(t * .pi / 3)) * rect.width / 2 : rect.midX,
                        y: sweepsV ? rect.midY + CGFloat(sin(t * .pi / 4)) * rect.height / 2 : rect.midY
                    )
            }
        }
    }

    private func handle(width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(.white).frame(width: width, height: height).shadow(color: .black.opacity(0.25), radius: 1.5)
    }

    @ViewBuilder
    private var readout: some View {
        HStack(spacing: 4) {
            if fixed {
                nudge("chevron.left", "Aim left") { step(h: -1) }
                Text(horizontalText(h)).frame(minWidth: 84)
                nudge("chevron.right", "Aim right") { step(h: 1) }
                Spacer()
                nudge("chevron.down", "Aim down") { step(v: -1) }
                Text(verticalText(v)).frame(minWidth: 84)
                nudge("chevron.up", "Aim up") { step(v: 1) }
            } else if following {
                Label { Text("Follows you across \(follow)°") } icon: { Image(systemName: "figure.walk") }
                Spacer()
            } else {
                if sweepsH {
                    Label { Text(verbatim: "\(horizontalText(sweep.left)) – \(horizontalText(sweep.right))") }
                        icon: { Image(systemName: "arrow.left.and.right") }
                }
                Spacer(minLength: 8)
                if sweepsV {
                    Label { Text(verbatim: "\(verticalText(sweep.down)) – \(verticalText(sweep.up))") }
                        icon: { Image(systemName: "arrow.up.and.down") }
                }
            }
        }
    }

    private var readoutText: String {
        if fixed { return "\(horizontalText(h)), \(verticalText(v))" }
        if following { return String(localized: "Follows you across \(follow)°") }
        return "\(horizontalText(sweep.left)) – \(horizontalText(sweep.right)), \(verticalText(sweep.down)) – \(verticalText(sweep.up))"
    }

    /// Moves the aim by whole steps (5° on most fans). Quick repeats become one command.
    private func step(h dh: Int = 0, v dv: Int = 0) {
        h = clamp(h + dh * (fan.horizontal?.step ?? 5), fan.horizontal?.range ?? hSpan)
        v = clamp(v + dv * (fan.vertical?.step ?? 5), fan.vertical?.range ?? vSpan)
        commit(after: 0.4)
    }

    private func nudge(_ icon: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    // MARK: geometry

    private func span(_ ranges: ClosedRange<Int>?...) -> ClosedRange<Int> {
        let all = ranges.compactMap { $0 }
        guard let low = all.map(\.lowerBound).min(), let high = all.map(\.upperBound).max(), low < high else {
            return -1...1
        }
        return low...high
    }

    private func x(_ h: Int, _ size: CGSize) -> CGFloat {
        let fraction = CGFloat(h - hSpan.lowerBound) / CGFloat(hSpan.upperBound - hSpan.lowerBound)
        return Self.inset + fraction * (size.width - 2 * Self.inset)
    }

    private func y(_ v: Int, _ size: CGSize) -> CGFloat {
        let fraction = CGFloat(v - vSpan.lowerBound) / CGFloat(vSpan.upperBound - vSpan.lowerBound)
        return Self.inset + (1 - fraction) * (size.height - 2 * Self.inset)
    }

    private func point(h: Int, v: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: x(h, size), y: y(v, size))
    }

    /// The angle under a point, rounded to the fan's step.
    private func angles(at point: CGPoint, in size: CGSize) -> (h: Int, v: Int) {
        func value(_ fraction: CGFloat, _ span: ClosedRange<Int>, _ step: Int) -> Int {
            let raw = Double(span.lowerBound) + Double(min(1, max(0, fraction))) * Double(span.upperBound - span.lowerBound)
            return Int((raw / Double(step)).rounded()) * step
        }
        return (
            value((point.x - Self.inset) / (size.width - 2 * Self.inset), hSpan, fan.horizontal?.step ?? 5),
            value(1 - (point.y - Self.inset) / (size.height - 2 * Self.inset), vSpan, fan.vertical?.step ?? 5)
        )
    }

    private func sweepRect(in size: CGSize) -> CGRect {
        let left = following ? x(-follow / 2, size) : sweepsH ? x(sweep.left, size) : Self.inset
        let right = following ? x(follow / 2, size) : sweepsH ? x(sweep.right, size) : size.width - Self.inset
        let top = sweepsV ? y(sweep.up, size) : Self.inset
        let bottom = sweepsV ? y(sweep.down, size) : size.height - Self.inset
        return CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }

    private func clamp(_ value: Int, _ range: ClosedRange<Int>?) -> Int {
        guard let range else { return value }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    // MARK: dragging

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                dragging = true
                focused = true
                if fixed {
                    aim(at: gesture.location, in: size)
                } else {
                    if edge == nil { edge = nearestEdge(to: gesture.startLocation, in: size) }
                    if let edge { move(edge, to: gesture.location, in: size) }
                }
            }
            .onEnded { gesture in
                if fixed { aim(at: gesture.location, in: size) }
                dragging = false
                edge = nil
                commit(after: 0)
            }
    }

    private func aim(at location: CGPoint, in size: CGSize) {
        let target = angles(at: location, in: size)
        h = clamp(target.h, fan.horizontal?.range)
        v = clamp(target.v, fan.vertical?.range)
    }

    private func nearestEdge(to point: CGPoint, in size: CGSize) -> Edge? {
        var edges: [(Edge, CGFloat)] = []
        if following { return point.x < x(0, size) ? .left : .right }
        if sweepsH {
            edges += [(.left, abs(point.x - x(sweep.left, size))), (.right, abs(point.x - x(sweep.right, size)))]
        }
        if sweepsV {
            edges += [(.up, abs(point.y - y(sweep.up, size))), (.down, abs(point.y - y(sweep.down, size)))]
        }
        return edges.min { $0.1 < $1.1 }?.0
    }

    /// Moves one edge, keeping it inside its limits and the minimum span from the other edge.
    private func move(_ edge: Edge, to location: CGPoint, in size: CGSize) {
        let target = angles(at: location, in: size)
        if following {  // both edges move together, snapped to the widths the fan offers
            let width = 2 * abs(target.h)
            follow = fan.followAngles.min { abs($0 - width) < abs($1 - width) } ?? follow
            return
        }
        let limits = fan.sweep
        switch edge {
        case .left:
            sweep.left = min(clamp(target.h, limits?.left?.range), sweep.right - (limits?.hSpacing ?? 0))
        case .right:
            sweep.right = max(clamp(target.h, limits?.right?.range), sweep.left + (limits?.hSpacing ?? 0))
        case .up:
            sweep.up = max(clamp(target.v, limits?.up?.range), sweep.down + (limits?.vSpacing ?? 0))
        case .down:
            sweep.down = min(clamp(target.v, limits?.down?.range), sweep.up - (limits?.vSpacing ?? 0))
        }
    }

    // MARK: syncing

    private func sync() {
        (h, v) = fan.angle
        let range = fan.oscRange
        sweep = (range.left, range.right, range.up, range.down)
        follow = fan.followAngle
    }

    private func commit(after delay: Double) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            pending = nil
            if !fan.on { store.send(["power_switch": true]) }  // the fan only takes a direction while on
            if fixed {
                var angle: JSON = [:]
                if fan.horizontal != nil { angle["H"] = h }
                if fan.vertical != nil { angle["V"] = v }
                store.send(["fixed_angle": angle])
            } else if following {
                store.send(["hwfpangle": String(follow)])  // the cloud lists these widths as text
            } else {
                store.send(["oscrange": ["L": sweep.left, "R": sweep.right, "U": sweep.up, "D": sweep.down]])
            }
        }
    }
}

func horizontalText(_ degrees: Int) -> String {
    if degrees == 0 { return String(localized: "Center") }
    return degrees < 0 ? String(localized: "\(-degrees)° left") : String(localized: "\(degrees)° right")
}

func verticalText(_ degrees: Int) -> String {
    if degrees == 0 { return String(localized: "Level") }
    return degrees < 0 ? String(localized: "\(-degrees)° down") : String(localized: "\(degrees)° up")
}

struct SwitchesCard: View {
    @EnvironmentObject var store: Store
    let fan: Fan

    var body: some View {
        Card(title: "Options", icon: "switch.2") {
            ForEach(fan.selects) { item in
                HStack {
                    Label(item.label, systemImage: item.icon)
                    Spacer()
                    Picker(item.label, selection: Binding(
                        get: { fan.state[item.directive] as? String ?? item.options[0] },
                        set: { store.send([item.directive: $0], turnOn: false) }
                    )) {
                        ForEach(item.options, id: \.self) { Text(optionLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
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
