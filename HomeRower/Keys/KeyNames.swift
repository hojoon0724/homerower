import Carbon

/// Human-readable names for keys, used when showing what Caps Lock is mapped to.
enum KeyNames {
    static func name(for keyCode: UInt16) -> String {
        if let name = specialNames[keyCode] { return name }
        if let character = KeyLabels.character(for: keyCode), !character.isEmpty {
            return character.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// A key sent with or without Shift, e.g. "{" or "Shift-A".
    static func name(for stroke: KeyStroke) -> String {
        guard stroke.isShifted else { return name(for: stroke.keyCode) }
        if let shifted = KeyLabels.character(for: stroke.keyCode, shifted: true), !shifted.isEmpty,
           shifted.uppercased() != KeyLabels.character(for: stroke.keyCode)?.uppercased() {
            return shifted
        }
        return "Shift-" + name(for: stroke.keyCode)
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

/// Looks up what a physical key types with the current keyboard input source.
enum KeyLabels {
    /// What a key types, or with `shifted` what it types with Shift (e.g. { for [).
    static func character(for keyCode: UInt16, shifted: Bool = false) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data

        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                // Modifier state in the form UCKeyTranslate wants: Carbon flags >> 8.
                shifted ? UInt32(shiftKey >> 8) & 0xFF : 0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
