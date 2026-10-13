import AppKit
import Carbon.HIToolbox

enum HotkeyAction: String, CaseIterable, Identifiable {
    case brightnessUp
    case brightnessDown
    case resolutionNext
    case resolutionPrevious
    case toggleHiDPI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brightnessUp: return "Increase brightness"
        case .brightnessDown: return "Decrease brightness"
        case .resolutionNext: return "Next resolution (more space)"
        case .resolutionPrevious: return "Previous resolution (larger text)"
        case .toggleHiDPI: return "Toggle HiDPI fix"
        }
    }

    var symbol: String {
        switch self {
        case .brightnessUp: return "sun.max.fill"
        case .brightnessDown: return "sun.min.fill"
        case .resolutionNext: return "arrow.up.left.and.arrow.down.right"
        case .resolutionPrevious: return "arrow.down.right.and.arrow.up.left"
        case .toggleHiDPI: return "sparkles.tv"
        }
    }

    static var defaults: [HotkeyAction: Shortcut] {
        let mods = UInt32(controlKey | optionKey | cmdKey)
        return [
            .brightnessUp: Shortcut(keyCode: UInt32(kVK_UpArrow), modifiers: mods, keyLabel: "↑"),
            .brightnessDown: Shortcut(keyCode: UInt32(kVK_DownArrow), modifiers: mods, keyLabel: "↓"),
            .resolutionNext: Shortcut(keyCode: UInt32(kVK_RightArrow), modifiers: mods, keyLabel: "→"),
            .resolutionPrevious: Shortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: mods, keyLabel: "←"),
            .toggleHiDPI: Shortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: mods, keyLabel: "H"),
        ]
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask
    var keyLabel: String

    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func keyLabel(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        ]
        if let label = special[Int(event.keyCode)] { return label }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

/// System-wide hotkeys via Carbon's RegisterEventHotKey (no Accessibility permission required).
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var handler: ((HotkeyAction) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: HotkeyAction] = [:]
    private var handlerInstalled = false

    func register(_ shortcuts: [HotkeyAction: Shortcut]) {
        unregisterAll()
        installHandlerIfNeeded()
        var nextID: UInt32 = 1
        for action in HotkeyAction.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4453_5054), id: nextID) // 'DSPT'
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[nextID] = action
            } else {
                NSLog("Displate: could not register \(shortcut.displayString) (\(status)); it may be used by another app")
            }
            nextID += 1
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        guard let action = actions[id] else { return }
        handler?(action)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, nil)
    }
}

private func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    Task { @MainActor in HotkeyManager.shared.fire(id) }
    return noErr
}
