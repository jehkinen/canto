import Carbon.HIToolbox
import CantoCore

/// Human-readable shortcut names, using the current keyboard layout for character keys.
enum KeyNames {
    static func symbols(for hotkey: Hotkey) -> [String] {
        if hotkey == .capsLock { return ["⇪"] }
        var parts: [String] = []
        if hotkey.modifiers.contains(.control) { parts.append("⌃") }
        if hotkey.modifiers.contains(.option) { parts.append("⌥") }
        if hotkey.modifiers.contains(.shift) { parts.append("⇧") }
        if hotkey.modifiers.contains(.command) { parts.append("⌘") }
        parts.append(name(for: hotkey.keyCode))
        return parts
    }

    static func description(for hotkey: Hotkey) -> String {
        hotkey == .capsLock ? "Caps Lock" : symbols(for: hotkey).joined()
    }

    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "Help",
        kVK_ANSI_KeypadEnter: "⌤",
    ]

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys[Int(keyCode)] != nil
    }

    static func name(for keyCode: UInt32) -> String {
        if let name = functionKeys[Int(keyCode)] ?? specialKeys[Int(keyCode)] { return name }
        return character(for: keyCode)?.uppercased() ?? String(format: "0x%02X", keyCode)
    }

    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
