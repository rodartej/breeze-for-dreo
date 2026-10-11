import SwiftUI

@main
struct BreezeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()
    @AppStorage("showInMenuBar", store: Store.defaults) private var showInMenuBar = false

    var body: some Scene {
        Window("Breeze", id: "main") {
            ContentView()
                .environmentObject(store)
                .containerBackground(.thickMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Fan") {
                Button("Turn On or Off") { store.togglePower() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Speed Up") { store.step(1) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Speed Down") { store.step(-1) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Divider()
                Button("Refresh") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
                Divider()
                Button("Sign Out") { store.logout() }
                    .disabled(!store.loggedIn)
            }
        }

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarPanel().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var showInMenuBar: Bool { Store.defaults.bool(forKey: "showInMenuBar") }

    /// Without the menu bar icon, closing the window quits. The fan keeps its settings either way.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !showInMenuBar
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // With the menu bar icon on, closing the window hides the app from the Dock.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.showInMenuBar, let closing = note.object as? NSWindow else { return }
            DispatchQueue.main.async {
                let stillOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.canBecomeMain }
                if !stillOpen { NSApp.setActivationPolicy(.accessory) }
            }
        }

        // Opened at login with the menu bar icon on: start quietly in the menu bar.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if atLogin, showInMenuBar {
            DispatchQueue.main.async {
                NSApp.windows.filter(\.canBecomeMain).forEach { $0.close() }
            }
        }
    }
}
