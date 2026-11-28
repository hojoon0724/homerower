import Foundation
import Testing
@testable import HomeRower

/// Layer keys in `HoldTapEngine`: "-" switches to Layer 1, where H acts as ← and J as ↓.
struct LayerEngineTests {
    private static let minus: UInt16 = 27
    private static let equal: UInt16 = 24
    private static let quote: UInt16 = 39
    private static let leftArrow: UInt16 = 123
    private static let downArrow: UInt16 = 125

    private func harness() -> EngineHarness {
        var settings = HoldTapEngine.Settings()
        settings.keyMap = [:]
        settings.layerKeys = [Self.minus: 1]
        settings.layerRemaps = [[KeyCode.h: KeyStroke(Self.leftArrow), KeyCode.j: KeyStroke(Self.downArrow)]]
        return EngineHarness(settings: settings)
    }

    @Test func tapTypesTheKey() {
        var h = harness()
        h.down(Self.minus, at: t0)
        h.up(Self.minus, at: t0 + 0.100)
        #expect(h.actions == tap(Self.minus))
    }

    @Test func holdingPastTheThresholdSwitchesLayers() {
        var h = harness()
        h.down(Self.minus, at: t0)
        h.advance(to: t0 + 0.250)
        h.down(KeyCode.h, at: t0 + 0.300)
        h.up(KeyCode.h, at: t0 + 0.350)
        h.up(Self.minus, at: t0 + 0.400)
        // The layer key itself never types.
        #expect(h.actions == tap(Self.leftArrow))
    }

    @Test func aKeyTappedWhileUndecidedIsAHold() {
        // -↓ H↓ H↑ -↑ within the threshold: permissive hold.
        var h = harness()
        h.down(Self.minus, at: t0)
        h.down(KeyCode.h, at: t0 + 0.050)
        h.up(KeyCode.h, at: t0 + 0.100)
        h.up(Self.minus, at: t0 + 0.150)
        #expect(h.actions == tap(Self.leftArrow))
    }

    @Test func aRollIsTwoCharacters() {
        // -↓ H↓ -↑ H↑: let go of - first, so it was typed, not held.
        var h = harness()
        h.down(Self.minus, at: t0)
        h.down(KeyCode.h, at: t0 + 0.050)
        h.up(Self.minus, at: t0 + 0.100)
        h.up(KeyCode.h, at: t0 + 0.150)
        // H's release goes out unchanged.
        #expect(h.actions == tap(Self.minus) + [press(KeyCode.h), .passThrough])
    }

    @Test func layerKeyPressedWhileTypingFastTypes() {
        // Pressed right after another key: the next key press makes it a character.
        var h = harness()
        h.down(KeyCode.g, at: t0)
        h.up(KeyCode.g, at: t0 + 0.050)
        h.down(Self.minus, at: t0 + 0.100)
        h.down(KeyCode.h, at: t0 + 0.130)
        h.up(KeyCode.h, at: t0 + 0.160)
        h.up(Self.minus, at: t0 + 0.190)
        // Keys with nothing to change go out unchanged.
        #expect(h.actions == [.passThrough, .passThrough, press(Self.minus), press(KeyCode.h), .passThrough, .passThrough])
    }

    @Test func aKeyReleasedAfterTheLayerGoesOffReleasesWhatItPressed() {
        var h = harness()
        h.down(Self.minus, at: t0)
        h.advance(to: t0 + 0.250)
        h.down(KeyCode.h, at: t0 + 0.300)
        h.up(Self.minus, at: t0 + 0.350)
        h.up(KeyCode.h, at: t0 + 0.400)
        #expect(h.actions == tap(Self.leftArrow))
    }

    @Test func keysTheLayerDoesntRemapKeepTheirHoldModifiers() {
        var settings = HoldTapEngine.Settings()
        settings.keyMap = [KeyCode.f: .leftCommand, KeyCode.j: .rightCommand]
        settings.layerKeys = [Self.minus: 1]
        settings.layerRemaps = [[KeyCode.h: KeyStroke(Self.leftArrow), KeyCode.j: KeyStroke(Self.downArrow)]]
        var h = EngineHarness(settings: settings)
        h.down(Self.minus, at: t0)
        h.advance(to: t0 + 0.250)
        // F passes through: still ⌘ when held.
        h.down(KeyCode.f, at: t0 + 0.300)
        h.advance(to: t0 + 0.550)
        h.down(KeyCode.h, at: t0 + 0.600)
        h.up(KeyCode.h, at: t0 + 0.650)
        h.up(KeyCode.f, at: t0 + 0.700)
        // J is remapped on the layer, so it's a plain ↓ there, not ⌘.
        h.down(KeyCode.j, at: t0 + 0.750)
        h.up(KeyCode.j, at: t0 + 0.800)
        h.up(Self.minus, at: t0 + 0.850)
        #expect(h.actions == [.modifier(.leftCommand, down: true)] + tap(Self.leftArrow)
            + [.modifier(.leftCommand, down: false)] + tap(Self.downArrow))
    }

    @Test func capsLockStandInActsAsItsTargetOnLayer0() {
        var settings = HoldTapEngine.Settings()
        settings.keyMap = [:]
        settings.baseRemaps = [Config.capsLockStandIn: KeyStroke(KeyCode.escape)]
        settings.layerKeys = [Self.minus: 1]
        settings.layerRemaps = [[Config.capsLockStandIn: KeyStroke(KeyCode.delete)]]
        var h = EngineHarness(settings: settings)
        h.down(Config.capsLockStandIn, at: t0)
        h.up(Config.capsLockStandIn, at: t0 + 0.050)
        h.down(Self.minus, at: t0 + 0.500)
        h.advance(to: t0 + 0.750)
        h.down(Config.capsLockStandIn, at: t0 + 0.800)
        h.up(Config.capsLockStandIn, at: t0 + 0.850)
        h.up(Self.minus, at: t0 + 0.900)
        #expect(h.actions == tap(KeyCode.escape) + tap(KeyCode.delete))
    }

    @Test func aShiftedRemapSendsShiftWithThatKeyAlone() {
        // On Layer 1, J acts as { (Shift-[); the H typed next stays unshifted.
        var settings = HoldTapEngine.Settings()
        settings.keyMap = [:]
        settings.layerKeys = [Self.minus: 1]
        settings.layerRemaps = [[KeyCode.j: KeyStroke(KeyCode.leftBracket, isShifted: true)]]
        var h = EngineHarness(settings: settings)
        h.down(Self.minus, at: t0)
        h.advance(to: t0 + 0.250)
        h.down(KeyCode.j, at: t0 + 0.300)
        h.repeatDown(KeyCode.j, at: t0 + 0.400)
        h.down(KeyCode.h, at: t0 + 0.450)
        h.up(KeyCode.j, at: t0 + 0.500)
        h.up(KeyCode.h, at: t0 + 0.550)
        h.up(Self.minus, at: t0 + 0.600)
        #expect(h.actions == [
            .key(KeyCode.leftBracket, down: true, isShifted: true),
            .key(KeyCode.leftBracket, down: true, isRepeat: true, isShifted: true),
            .passThrough,
            .key(KeyCode.leftBracket, down: false, isShifted: true),
            .passThrough,
        ])
    }

    @Test func otherLayerKeysJustTypeOnceALayerIsOn() {
        // - and = both switch to Layer 1, and ' to Layer 2. Holding - then = or ' types
        // them, without moving to another layer.
        var settings = HoldTapEngine.Settings()
        settings.keyMap = [:]
        settings.layerKeys = [Self.minus: 1, Self.equal: 1, Self.quote: 2]
        settings.layerRemaps = [[KeyCode.h: KeyStroke(Self.leftArrow)], [KeyCode.h: KeyStroke(Self.downArrow)]]
        var h = EngineHarness(settings: settings)
        h.down(Self.minus, at: t0)
        h.advance(to: t0 + 0.250)
        h.down(Self.equal, at: t0 + 0.300)
        h.up(Self.equal, at: t0 + 0.350)
        h.down(Self.quote, at: t0 + 0.400)
        h.advance(to: t0 + 0.700)
        h.down(KeyCode.h, at: t0 + 0.750)
        h.up(KeyCode.h, at: t0 + 0.800)
        h.up(Self.quote, at: t0 + 0.850)
        h.up(Self.minus, at: t0 + 0.900)
        #expect(h.actions == [.passThrough, .passThrough, .passThrough] + tap(Self.leftArrow) + [.passThrough])
    }

    @Test func anyOfALayersKeysSwitchesToIt() {
        var settings = HoldTapEngine.Settings()
        settings.keyMap = [:]
        settings.layerKeys = [Self.minus: 1, Self.equal: 1]
        settings.layerRemaps = [[KeyCode.h: KeyStroke(Self.leftArrow)]]
        var h = EngineHarness(settings: settings)
        h.down(Self.equal, at: t0)
        h.advance(to: t0 + 0.250)
        h.down(KeyCode.h, at: t0 + 0.300)
        h.up(KeyCode.h, at: t0 + 0.350)
        h.up(Self.equal, at: t0 + 0.400)
        #expect(h.actions == tap(Self.leftArrow))
    }
}
