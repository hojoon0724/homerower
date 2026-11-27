import Foundation

/// Remaps Caps Lock to another key with `hidutil`.
///
/// This happens at the HID driver level, before the event tap, so it works in every app and
/// avoids Caps Lock's toggle and delay behavior. The mapping lasts until it's cleared or the
/// Mac restarts.
enum CapsLockRemap {
    static let capsLockKeyCode: UInt16 = 57

    /// Applies the mapping, or clears it when `keyCode` is `nil` or Caps Lock itself.
    /// Returns `false` if the key can't be mapped or `hidutil` fails.
    ///
    /// Note: this replaces the whole `UserKeyMapping` property, including mappings made by
    /// other tools.
    @discardableResult
    static func apply(target keyCode: UInt16?) -> Bool {
        var mappings: [[String: UInt64]] = []
        if let keyCode, keyCode != capsLockKeyCode {
            guard let usage = hidUsages[keyCode] else { return false }
            mappings.append([
                "HIDKeyboardModifierMappingSrc": keyboardPage | capsLockUsage,
                "HIDKeyboardModifierMappingDst": keyboardPage | usage,
            ])
        }
        guard let json = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": mappings]),
              let argument = String(data: json, encoding: .utf8) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", argument]
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }

    /// Whether Caps Lock can be turned into this key.
    static func canMap(to keyCode: UInt16) -> Bool {
        keyCode == capsLockKeyCode || hidUsages[keyCode] != nil
    }

    // MARK: - HID usages

    /// Keyboard/keypad usage page (0x07), shifted into hidutil's 64-bit format.
    private static let keyboardPage: UInt64 = 0x7_0000_0000
    private static let capsLockUsage: UInt64 = 0x39

    /// Virtual key code → HID keyboard usage.
    private static let hidUsages: [UInt16: UInt64] = [
        // Letters
        0: 0x04, 11: 0x05, 8: 0x06, 2: 0x07, 14: 0x08, 3: 0x09, 5: 0x0A, 4: 0x0B,
        34: 0x0C, 38: 0x0D, 40: 0x0E, 37: 0x0F, 46: 0x10, 45: 0x11, 31: 0x12, 35: 0x13,
        12: 0x14, 15: 0x15, 1: 0x16, 17: 0x17, 32: 0x18, 9: 0x19, 13: 0x1A, 7: 0x1B,
        16: 0x1C, 6: 0x1D,
        // Number row
        18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 23: 0x22, 22: 0x23, 26: 0x24, 28: 0x25,
        25: 0x26, 29: 0x27,
        // Editing and punctuation
        36: 0x28, 53: 0x29, 51: 0x2A, 48: 0x2B, 49: 0x2C, 27: 0x2D, 24: 0x2E, 33: 0x2F,
        30: 0x30, 42: 0x31, 41: 0x33, 39: 0x34, 50: 0x35, 43: 0x36, 47: 0x37, 44: 0x38,
        // Function keys
        122: 0x3A, 120: 0x3B, 99: 0x3C, 118: 0x3D, 96: 0x3E, 97: 0x3F, 98: 0x40, 100: 0x41,
        101: 0x42, 109: 0x43, 103: 0x44, 111: 0x45, 105: 0x68, 107: 0x69, 113: 0x6A,
        106: 0x6B, 64: 0x6C, 79: 0x6D, 80: 0x6E, 90: 0x6F,
        // Navigation
        115: 0x4A, 116: 0x4B, 117: 0x4C, 119: 0x4D, 121: 0x4E,
        124: 0x4F, 123: 0x50, 125: 0x51, 126: 0x52,
        // Modifiers
        59: 0xE0, 56: 0xE1, 58: 0xE2, 55: 0xE3, 62: 0xE4, 60: 0xE5, 61: 0xE6, 54: 0xE7,
    ]
}

/// Human-readable names for keys, used when showing what Caps Lock is mapped to.
enum KeyNames {
    static func name(for keyCode: UInt16) -> String {
        if let name = specialNames[keyCode] { return name }
        if let character = KeyLabels.character(for: keyCode), !character.isEmpty {
            return character.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static let specialNames: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 57: "Caps Lock",
        117: "Fwd Delete", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        59: "Left ⌃", 62: "Right ⌃", 56: "Left ⇧", 60: "Right ⇧",
        58: "Left ⌥", 61: "Right ⌥", 55: "Left ⌘", 54: "Right ⌘", 63: "fn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
}
