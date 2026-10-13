import AppKit
import ApplicationServices

/// Intercepts the keyboard's brightness keys (F1/F2 and the Touch Bar / Control Strip equivalents)
/// so they also work on external monitors. Needs Accessibility permission for the event tap.
/// Displays macOS controls natively (built-in, Studio Display…) are left to macOS.
@MainActor
final class MediaKeys {
    static let shared = MediaKeys()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate var swallowedKeyUps: Set<Int> = []

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Starts or stops the tap to match the setting and permission state.
    func update() {
        if AppState.shared.useBrightnessKeys && Self.isTrusted {
            start()
        } else {
            stop()
        }
    }

    /// Shows the system Accessibility prompt and opens the right Settings pane.
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << 14 // NX_SYSDEFINED (media & brightness keys)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: mediaKeyCallback, userInfo: nil) else {
            NSLog("Displate: could not create the brightness key event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        swallowedKeyUps.removeAll()
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

private let brightnessUpKey = 2   // NX_KEYTYPE_BRIGHTNESS_UP
private let brightnessDownKey = 3 // NX_KEYTYPE_BRIGHTNESS_DOWN

private func mediaKeyCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { MediaKeys.shared.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = (nsEvent.data1 & 0xFFFF_0000) >> 16
    guard keyCode == brightnessUpKey || keyCode == brightnessDownKey else {
        return Unmanaged.passUnretained(event)
    }
    let keyState = (nsEvent.data1 & 0x0000_FF00) >> 8
    let isDown = keyState == 0x0A
    let flags = nsEvent.modifierFlags
    let fine = flags.contains(.option) && flags.contains(.shift)

    // The tap's run loop source lives on the main run loop, so this runs on the main thread.
    let handled: Bool = MainActor.assumeIsolated {
        if isDown {
            let handled = AppState.shared.handleBrightnessKey(up: keyCode == brightnessUpKey, fine: fine)
            if handled { MediaKeys.shared.swallowedKeyUps.insert(keyCode) }
            return handled
        }
        return MediaKeys.shared.swallowedKeyUps.remove(keyCode) != nil
    }
    return handled ? nil : Unmanaged.passUnretained(event)
}
