// Store tests against FakeDreo. Run with `make test`.
import Foundation

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        print("✓ \(message)")
    } else {
        failures += 1
        print("✗ \(message) (line \(line))")
    }
}

/// Long enough for queued commands (0.3 s each in the fake) plus the 2 s confirmation read.
@MainActor func settle() async { try? await Task.sleep(for: .seconds(3.8)) }

@MainActor func run() async {
    let store = Store()
    try? await Task.sleep(for: .seconds(1.5))
    guard let fan = store.fan else {
        print("✗ no fan loaded: \(store.message ?? "")")
        exit(1)
    }

    expect(fan.speeds == 1...9, "reads the speed range from the model config")
    expect(fan.modes.count == 6, "reads the preset modes")
    expect(fan.oscModes == ["Fixed", "Horizontal", "Vertical", "Both", "SmartFollow"], "knows the oscillation modes")
    expect(fan.horizontal?.range == -75...75 && fan.vertical?.step == 5, "reads the fixed-angle ranges")
    expect(fan.toggles.map(\.field).sorted() == ["childlock_switch", "mute_switch"], "reads the switches")
    expect(fan.angle == (15, 0) && fan.oscRange.left == -45, "parses angles sent as strings")
    expect(fan.oscModes.last == "SmartFollow" && fan.followAngles == [30, 40, 50, 60, 70, 80, 90, 100],
           "reads selects sent as a list (oscillation modes, follow widths)")
    expect(fan.selects.map(\.directive) == ["lightmode"] && fan.followAngle == 60, "reads the display setting")

    store.step(3)
    store.send(["oscmode": "Both"])
    store.send(["childlock_switch": true], turnOn: false)
    expect(fan.speed == 7 && fan.oscMode == "Both", "updates the UI before the cloud answers")
    await settle()
    expect(fan.speed == 7 && fan.oscMode == "Both" && fan.state["childlock_switch"] as? Bool == true,
           "the cloud confirms queued commands in order")

    store.send(["oscmode": "Fixed"])
    store.send(["fixed_angle": ["H": -20, "V": 10]])
    store.togglePower()
    await settle()
    expect(!fan.on && fan.angle == (-20, 10), "sets the angle and turns off")

    // The demo cloud reports changes 3 s late (BREEZE_DEMO_LAG), like the real one.
    store.send(["fixed_angle": ["H": 35, "V": 20]])
    try? await Task.sleep(for: .seconds(2.6))  // the confirmation read comes back stale
    expect(fan.angle == (35, 20), "a lagging cloud doesn't undo a new angle")
    await settle()
    await store.refresh()
    expect(fan.angle == (35, 20), "keeps the angle once the cloud catches up")

    store.send(["oscmode": "Both"])
    store.send(["oscrange": ["L": -60, "R": 30, "U": 75, "D": -15]])
    await settle()
    await store.refresh()
    let range = fan.oscRange
    expect(fan.oscMode == "Both" && range.left == -60 && range.right == 30 && range.up == 75 && range.down == -15,
           "sets the oscillation range")
    expect(fan.sweep?.hSpacing == 30 && fan.sweep?.left?.range == -75...45, "reads the oscillation limits")

    store.send(["oscmode": "SmartFollow"])
    store.send(["hwfpangle": "90"])
    await settle()
    await store.refresh()
    expect(fan.oscMode == "SmartFollow" && fan.followAngle == 90, "sets how wide SmartFollow follows")

    store.send(["mode": "Turbo"])
    await settle()
    expect(fan.on && fan.mode == "Turbo", "choosing a mode while off turns the fan on")

    store.send(["mute_switch": true], turnOn: false)
    store.togglePower()
    await settle()
    store.send(["mute_switch": false], turnOn: false)
    await settle()
    expect(!fan.on, "switches marked turnOn: false don't power the fan on")

    store.choose(store.fans[1])
    try? await Task.sleep(for: .seconds(1))
    expect(store.fan?.model == "DR-HTF008S" && store.fan?.oscillate == true, "switches to the tower fan")
    store.choose(store.fans[0])

    print(failures == 0 ? "\nAll tests passed." : "\n\(failures) test(s) failed.")
    exit(failures == 0 ? 0 : 1)
}

Task { await run() }
dispatchMain()
