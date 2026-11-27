import CoreGraphics
import Testing
@testable import HomeRower

/// Consistency checks for the hand-written key tables: default key map, hands,
/// modifier flags, Caps Lock usages and the drawn keyboard layout.
@MainActor
struct KeyTableTests {
    // MARK: - Hands and default key map

    @Test func handSetsDontOverlap() {
        #expect(Config.leftHandKeys.isDisjoint(with: Config.rightHandKeys))
    }

    @Test func defaultHomeRowModsSitOnTheMatchingHand() {
        for (keyCode, modifiers) in Config.homeRowMods {
            for modifier in modifiers.modifiers {
                #expect(Config.hand(of: keyCode) == (modifier.isLeft ? .left : .right), "\(modifier)")
            }
        }
    }

    @Test func defaultKeyMapUsesEveryModifierOnce() {
        #expect(Config.homeRowMods.values.allSatisfy { $0.modifiers.count == 1 })
        #expect(Set(Config.homeRowMods.values.flatMap(\.modifiers)) == Set(Modifier.allCases))
        #expect(Config.homeRowMods.count == Modifier.allCases.count)
    }

    @Test func keysOutsideTheLetterBlockHaveNoHand() {
        #expect(Config.hand(of: KeyCode.space) == nil)
        #expect(Config.hand(of: KeyCode.capsLock) == nil)
        #expect(Config.hand(of: KeyCode.leftShift) == nil)
    }

    // MARK: - Modifiers

    @Test func modifierKeyCodesAreDistinct() {
        #expect(Set(Modifier.allCases.map(\.keyCode)).count == Modifier.allCases.count)
    }

    @Test func modifierSideMatchesItsName() {
        for modifier in Modifier.allCases {
            #expect(modifier.displayName.hasPrefix(modifier.side))
            #expect(modifier.rawValue.hasPrefix(modifier.isLeft ? "left" : "right"))
        }
    }

    @Test func modifierFlagsTellLeftFromRight() {
        let generic: [Modifier: CGEventFlags] = [
            .leftShift: .maskShift, .rightShift: .maskShift,
            .leftControl: .maskControl, .rightControl: .maskControl,
            .leftOption: .maskAlternate, .rightOption: .maskAlternate,
            .leftCommand: .maskCommand, .rightCommand: .maskCommand,
        ]
        for modifier in Modifier.allCases {
            #expect(modifier.flags.contains(generic[modifier]!), "\(modifier)")
        }
        // The device-dependent bit is what makes each one unique.
        #expect(Set(Modifier.allCases.map(\.flags.rawValue)).count == Modifier.allCases.count)
    }

    // MARK: - Caps Lock

    @Test func capsLockCanActAsCommonKeys() {
        for keyCode in [KeyCode.escape, KeyCode.a, KeyCode.leftControl, KeyCode.delete, KeyCode.capsLock] {
            #expect(CapsLockRemap.canMap(to: keyCode), "\(KeyNames.name(for: keyCode))")
        }
    }

    @Test func capsLockCantActAsFn() {
        // fn isn't a HID keyboard usage that hidutil can map to.
        #expect(!CapsLockRemap.canMap(to: KeyCode.function))
    }

    @Test func specialKeysHaveFixedNames() {
        #expect(KeyNames.name(for: KeyCode.escape) == "Esc")
        #expect(KeyNames.name(for: KeyCode.capsLock) == "Caps Lock")
        #expect(KeyNames.name(for: KeyCode.leftCommand) == "Left ⌘")
    }

    // MARK: - Drawn keyboard

    @Test func everyRowFillsTheKeyboardWidth() {
        for row in KeySpec.rows {
            #expect(row.keys.reduce(0) { $0 + $1.width } == KeySpec.rowWidth, "row \(row.id)")
        }
    }

    @Test func everyKeyAppearsOnce() {
        let keyCodes = KeySpec.rows.flatMap(\.keys).map(\.keyCode)
        #expect(Set(keyCodes).count == keyCodes.count)
    }

    @Test func defaultHomeRowKeysAreOnTheKeyboardAndMappable() {
        let keys = Dictionary(uniqueKeysWithValues: KeySpec.rows.flatMap(\.keys).map { ($0.keyCode, $0) })
        for keyCode in Config.homeRowMods.keys {
            #expect(keys[keyCode]?.isMappable == true, "key \(keyCode)")
        }
    }

    @Test func symbolKeysShowTheirSymbol() {
        #expect(KeySpec.displayName(for: KeyCode.returnKey) == "↩")
        #expect(KeySpec.displayName(for: KeyCode.tab) == "⇥")
        #expect(KeySpec.displayName(for: KeyCode.escape) == "Esc")
    }
}
