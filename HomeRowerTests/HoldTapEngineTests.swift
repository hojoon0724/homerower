import Foundation
import Testing
@testable import HomeRower

struct HoldTapEngineTests {
    @Test func quickTapTypesLetter() {
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.up(KeyCode.a, at: t0 + 0.100)
        #expect(h.actions == tap(KeyCode.a))
    }

    @Test func longPressIsModifierOnly() {
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.advance(to: t0 + 0.250)
        h.up(KeyCode.a, at: t0 + 0.250)
        #expect(h.actions == [.modifier(.leftShift, down: true), .modifier(.leftShift, down: false)])
    }

    @Test func longPressWithoutTimerStillHolds() {
        // The timer may not have fired yet when the next event arrives.
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.up(KeyCode.a, at: t0 + 0.250)
        #expect(h.actions == [.modifier(.leftShift, down: true), .modifier(.leftShift, down: false)])
    }

    @Test func oppositeHandRollTypesBothLetters() {
        // A↓ J↓ A↑ J↑ → "ah"
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.j, at: t0 + 0.050)
        h.up(KeyCode.a, at: t0 + 0.100)
        h.up(KeyCode.j, at: t0 + 0.150)
        #expect(h.actions == tap(KeyCode.a) + tap(KeyCode.j))
    }

    @Test func permissiveHoldGivesShiftedKey() {
        // A↓ J↓ J↑ A↑ → Shift+J
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.j, at: t0 + 0.050)
        h.up(KeyCode.j, at: t0 + 0.100)
        h.up(KeyCode.a, at: t0 + 0.150)
        #expect(h.actions == [.modifier(.leftShift, down: true)] + tap(KeyCode.j) + [.modifier(.leftShift, down: false)])
    }

    @Test func permissiveHoldWithNonHomeRowKey() {
        // A↓ P↓ P↑ A↑ → Shift+P
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.p, at: t0 + 0.050)
        h.up(KeyCode.p, at: t0 + 0.100)
        h.up(KeyCode.a, at: t0 + 0.150)
        #expect(h.actions == [.modifier(.leftShift, down: true)] + tap(KeyCode.p) + [.modifier(.leftShift, down: false)])
    }

    @Test func sameHandHomeRowRollTypesBothLetters() {
        // S↓ D↓ D↑ S↑ (same hand, Control then Option) → "sd"
        var h = EngineHarness()
        h.down(KeyCode.s, at: t0)
        h.down(KeyCode.d, at: t0 + 0.050)
        h.up(KeyCode.d, at: t0 + 0.100)
        h.up(KeyCode.s, at: t0 + 0.150)
        // S's physical key up flows through as a normal event.
        #expect(h.actions == [press(KeyCode.s)] + tap(KeyCode.d) + [.passThrough])
    }

    @Test func sameHandRollReleasedInOrder() {
        // F↓ D↓ F↑ D↑ → "ue"
        var h = EngineHarness()
        h.down(KeyCode.f, at: t0)
        h.down(KeyCode.d, at: t0 + 0.050)
        h.up(KeyCode.f, at: t0 + 0.100)
        h.up(KeyCode.d, at: t0 + 0.150)
        #expect(h.actions == tap(KeyCode.f) + tap(KeyCode.d))
    }

    @Test func sameHandNonModKeyForcesTap() {
        // S↓ E↓ → S (Control) is a tap as soon as E goes down.
        var h = EngineHarness()
        h.down(KeyCode.s, at: t0)
        h.down(KeyCode.e, at: t0 + 0.050)
        #expect(h.actions == [press(KeyCode.s), press(KeyCode.e)])
        h.up(KeyCode.e, at: t0 + 0.100)
        h.up(KeyCode.s, at: t0 + 0.150)
        #expect(h.actions == [press(KeyCode.s), press(KeyCode.e), .passThrough, .passThrough])
    }

    @Test func typingSpeedRuleTapsOnNextKey() {
        // X↓ X↑, then S↓ within 150 ms, J↓ J↑ S↑ → "xsj": during fast typing the next
        // key press makes S a letter, even though J is released inside S (no permissive hold).
        var h = EngineHarness()
        h.down(KeyCode.x, at: t0)
        h.up(KeyCode.x, at: t0 + 0.050)
        h.down(KeyCode.s, at: t0 + 0.100)
        h.down(KeyCode.j, at: t0 + 0.150)
        h.up(KeyCode.j, at: t0 + 0.200)
        h.up(KeyCode.s, at: t0 + 0.250)
        #expect(h.actions == [.passThrough, .passThrough, press(KeyCode.s)] + tap(KeyCode.j) + [.passThrough])
    }

    @Test func combinationHoldsEveryModifier() {
        // F as ⌥⌘: held, then T → Option+Command+T, released in reverse order.
        var h = EngineHarness(settings: .init(keyMap: [KeyCode.f: [.leftOption, .leftCommand]]))
        h.down(KeyCode.f, at: t0)
        h.advance(to: t0 + 0.250)
        h.down(KeyCode.t, at: t0 + 0.300)
        h.up(KeyCode.t, at: t0 + 0.350)
        h.up(KeyCode.f, at: t0 + 0.400)
        #expect(h.actions == [
            .modifier(.leftOption, down: true),
            .modifier(.leftCommand, down: true),
            .passThrough,
            .passThrough,
            .modifier(.leftCommand, down: false),
            .modifier(.leftOption, down: false),
        ])
        #expect(h.engine.activeModifiers.isEmpty)
    }

    @Test func shiftCombinationFollowsTheStrictRules() {
        // ⇧⌘ is chorded slowly like any shortcut, so a same-hand key still makes it a letter.
        var h = EngineHarness(settings: .init(keyMap: [KeyCode.a: [.leftShift, .leftCommand]]))
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.e, at: t0 + 0.050)
        #expect(h.actions == [press(KeyCode.a), press(KeyCode.e)])
    }

    @Test func capsLockStandInHoldsDuringFastTyping() {
        // Caps Lock (as its stand-in) for Control, pressed right after typing, then C on the
        // same side: Control+C. Keys outside the letter block are decided by release order.
        var h = EngineHarness(settings: .init(keyMap: [Config.capsLockStandIn: .leftControl]))
        h.down(KeyCode.x, at: t0)
        h.up(KeyCode.x, at: t0 + 0.050)
        h.down(Config.capsLockStandIn, at: t0 + 0.080)
        h.down(KeyCode.c, at: t0 + 0.110)
        h.up(KeyCode.c, at: t0 + 0.150)
        h.up(Config.capsLockStandIn, at: t0 + 0.180)
        #expect(h.actions == [.passThrough, .passThrough, .modifier(.leftControl, down: true)]
            + tap(KeyCode.c) + [.modifier(.leftControl, down: false)])
    }

    @Test func capsLockStandInTapIsAKeyTap() {
        // The event tap turns this tap into a Caps Lock toggle.
        var h = EngineHarness(settings: .init(keyMap: [Config.capsLockStandIn: .leftControl]))
        h.down(Config.capsLockStandIn, at: t0)
        h.up(Config.capsLockStandIn, at: t0 + 0.080)
        #expect(h.actions == tap(Config.capsLockStandIn))
    }

    // MARK: - Shift: decided by release order

    @Test func shiftWithSameHandKeyGivesCapital() {
        // Dvorak "G": ;↓ (Right Shift) U↓ U↑ ;↑, all quick and on the same hand → Shift+U.
        var h = EngineHarness()
        h.down(KeyCode.semicolon, at: t0)
        h.down(KeyCode.u, at: t0 + 0.040)
        h.up(KeyCode.u, at: t0 + 0.090)
        h.up(KeyCode.semicolon, at: t0 + 0.120)
        #expect(h.actions == [.modifier(.rightShift, down: true)] + tap(KeyCode.u) + [.modifier(.rightShift, down: false)])
    }

    @Test func shiftDuringFastTypingGivesCapital() {
        // X↓ X↑, then A↓ right after, T↓ T↑ A↑ → "x", then Shift+T: fast typing doesn't
        // make Shift a letter.
        var h = EngineHarness()
        h.down(KeyCode.x, at: t0)
        h.up(KeyCode.x, at: t0 + 0.050)
        h.down(KeyCode.a, at: t0 + 0.080)
        h.down(KeyCode.t, at: t0 + 0.110)
        h.up(KeyCode.t, at: t0 + 0.150)
        h.up(KeyCode.a, at: t0 + 0.170)
        #expect(h.actions == [.passThrough, .passThrough, .modifier(.leftShift, down: true)]
            + tap(KeyCode.t) + [.modifier(.leftShift, down: false)])
    }

    @Test func shiftReleasedFirstTypesBothLetters() {
        // A↓ E↓ A↑ E↑ (a same-hand roll) → "ae": A goes up first, so it was a letter.
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.e, at: t0 + 0.040)
        h.up(KeyCode.a, at: t0 + 0.080)
        h.up(KeyCode.e, at: t0 + 0.120)
        #expect(h.actions == tap(KeyCode.a) + [press(KeyCode.e), .passThrough])
    }

    @Test func shiftWithSameHandHomeRowKeyGivesCapital() {
        // A↓ S↓ S↑ A↑ → Shift+S, not the "as" roll other modifiers would give.
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.s, at: t0 + 0.050)
        h.up(KeyCode.s, at: t0 + 0.100)
        h.up(KeyCode.a, at: t0 + 0.150)
        #expect(h.actions == [.modifier(.leftShift, down: true)] + tap(KeyCode.s) + [.modifier(.leftShift, down: false)])
    }

    @Test func shiftFollowsTheStrictRulesWhenTurnedOff() {
        // Same keys as `shiftWithSameHandKeyGivesCapital`: "sg"-style letters.
        var h = EngineHarness(settings: .init(shiftDecidedByRelease: false))
        h.down(KeyCode.semicolon, at: t0)
        h.down(KeyCode.u, at: t0 + 0.040)
        h.up(KeyCode.u, at: t0 + 0.090)
        h.up(KeyCode.semicolon, at: t0 + 0.120)
        #expect(h.actions == [press(KeyCode.semicolon), press(KeyCode.u), .passThrough, .passThrough])
    }

    @Test func holdRightAfterAnotherKeyIsStillModifier() {
        // H↓ H↑, A↓ right after and held → Shift, then T gives Shift+T.
        var h = EngineHarness()
        h.down(KeyCode.h, at: t0)
        h.up(KeyCode.h, at: t0 + 0.050)
        h.down(KeyCode.a, at: t0 + 0.080)
        h.advance(to: t0 + 0.350)
        h.down(KeyCode.t, at: t0 + 0.400)
        h.up(KeyCode.t, at: t0 + 0.450)
        h.up(KeyCode.a, at: t0 + 0.500)
        #expect(h.actions == [
            .passThrough,
            .passThrough,
            .modifier(.leftShift, down: true),
            .passThrough,
            .passThrough,
            .modifier(.leftShift, down: false),
        ])
    }

    @Test func holdWhilePreviousKeyStillDownIsStillModifier() {
        // H↓, A↓ before H is released, H↑, A held → Shift.
        var h = EngineHarness()
        h.down(KeyCode.h, at: t0)
        h.down(KeyCode.a, at: t0 + 0.050)
        h.up(KeyCode.h, at: t0 + 0.100)
        h.advance(to: t0 + 0.300)
        h.up(KeyCode.a, at: t0 + 0.400)
        // H's release goes straight out: it was pressed before A, so A doesn't affect it.
        #expect(h.actions == [
            .passThrough,
            .passThrough,
            .modifier(.leftShift, down: true),
            .modifier(.leftShift, down: false),
        ])
    }

    @Test func releaseOfEarlierKeyIsNotHeldBack() {
        // From a real log: O↓ D↓ O↑, D held. O's release must go out at once, before D's
        // Option, or O looks held and gets the modifier (accent popup "ř" in Dvorak).
        var h = EngineHarness()
        h.down(KeyCode.o, at: t0)
        h.down(KeyCode.d, at: t0 + 0.020)
        h.up(KeyCode.o, at: t0 + 0.031)
        #expect(h.actions == [.passThrough, .passThrough])
        h.advance(to: t0 + 0.300)
        h.repeatDown(KeyCode.d, at: t0 + 0.270)
        h.up(KeyCode.d, at: t0 + 0.400)
        #expect(h.actions == [
            .passThrough,
            .passThrough,
            .modifier(.leftOption, down: true),
            .modifier(.leftOption, down: false),
        ])
    }

    @Test func repeatsOfEarlierKeyKeepComing() {
        // X held and repeating, then A pressed: X's repeats aren't held back by A.
        var h = EngineHarness()
        h.down(KeyCode.x, at: t0)
        h.repeatDown(KeyCode.x, at: t0 + 0.500)
        h.down(KeyCode.a, at: t0 + 0.520)
        h.repeatDown(KeyCode.x, at: t0 + 0.550)
        h.up(KeyCode.x, at: t0 + 0.580)
        h.up(KeyCode.a, at: t0 + 0.600)
        #expect(h.actions == [.passThrough, .passThrough, .passThrough, .passThrough] + tap(KeyCode.a))
    }

    @Test func stackedModifiersCommandShiftQ() {
        // F↓ A↓ (hold) Q↓ Q↑ → Cmd+Shift+Q
        var h = EngineHarness()
        h.down(KeyCode.f, at: t0)
        h.down(KeyCode.a, at: t0 + 0.050)
        h.advance(to: t0 + 0.300)
        h.down(KeyCode.q, at: t0 + 0.300)
        h.up(KeyCode.q, at: t0 + 0.350)
        #expect(h.actions == [
            .modifier(.leftCommand, down: true),
            .modifier(.leftShift, down: true),
            .passThrough,
            .passThrough,
        ])
        #expect(h.engine.activeModifiers == [.leftCommand, .leftShift])
    }

    @Test func quickSameHandChordWithOppositeHandKey() {
        // F↓ D↓ I↓ I↑ D↑ F↑, all quick → Cmd+Opt+I. D follows F fast, but as part of a
        // chord it must not be caught by the typing-speed rule.
        var h = EngineHarness()
        h.down(KeyCode.f, at: t0)
        h.down(KeyCode.d, at: t0 + 0.030)
        h.down(KeyCode.i, at: t0 + 0.080)
        h.up(KeyCode.i, at: t0 + 0.120)
        h.up(KeyCode.d, at: t0 + 0.150)
        h.up(KeyCode.f, at: t0 + 0.160)
        #expect(h.actions == [
            .modifier(.leftCommand, down: true),
            .modifier(.leftOption, down: true),
        ] + tap(KeyCode.i) + [
            .modifier(.leftOption, down: false),
            .modifier(.leftCommand, down: false),
        ])
    }

    @Test func quickCrossHandChord() {
        // F↓ K↓ T↓ T↑ K↑ F↑ → Cmd+Opt+T: T is on F's hand, but K is on the other one.
        var h = EngineHarness()
        h.down(KeyCode.f, at: t0)
        h.down(KeyCode.k, at: t0 + 0.030)
        h.down(KeyCode.t, at: t0 + 0.080)
        h.up(KeyCode.t, at: t0 + 0.120)
        h.up(KeyCode.k, at: t0 + 0.150)
        h.up(KeyCode.f, at: t0 + 0.160)
        #expect(h.actions == [
            .modifier(.leftCommand, down: true),
            .modifier(.rightOption, down: true),
        ] + tap(KeyCode.t) + [
            .modifier(.rightOption, down: false),
            .modifier(.leftCommand, down: false),
        ])
    }

    @Test func heldModifierDisablesTypingSpeedRule() {
        // Hold F (Cmd), then quickly tap J: J must still be decided, not passed through raw.
        var h = EngineHarness()
        h.down(KeyCode.f, at: t0)
        h.advance(to: t0 + 0.250)
        h.down(KeyCode.j, at: t0 + 0.260)
        h.up(KeyCode.j, at: t0 + 0.300)
        h.up(KeyCode.f, at: t0 + 0.350)
        #expect(h.actions == [.modifier(.leftCommand, down: true)] + tap(KeyCode.j) + [.modifier(.leftCommand, down: false)])
    }

    @Test func customKeyMapIsUsed() {
        // G mapped to Command, A unmapped: A passes straight through, G holds Command.
        var h = EngineHarness(settings: .init(keyMap: [KeyCode.g: .leftCommand]))
        h.down(KeyCode.a, at: t0)
        h.up(KeyCode.a, at: t0 + 0.050)
        h.down(KeyCode.g, at: t0 + 1)
        h.advance(to: t0 + 1.250)
        h.up(KeyCode.g, at: t0 + 1.300)
        #expect(h.actions == [
            .passThrough,
            .passThrough,
            .modifier(.leftCommand, down: true),
            .modifier(.leftCommand, down: false),
        ])
    }

    @Test func resetReleasesHeldModifiers() {
        var h = EngineHarness()
        h.down(KeyCode.semicolon, at: t0)
        h.advance(to: t0 + 0.250)
        #expect(h.engine.reset() == [.modifier(.rightShift, down: false)])
        #expect(h.engine.activeModifiers.isEmpty)
    }

    // MARK: - Edge cases

    @Test func unmappedKeyPassesThrough() {
        var h = EngineHarness()
        h.down(KeyCode.x, at: t0)
        h.up(KeyCode.x, at: t0 + 0.050)
        #expect(h.actions == [.passThrough, .passThrough])
    }

    @Test func firstPressRequestsTimerForFullTappingTerm() {
        var engine = HoldTapEngine()
        let actions = engine.handle(KeyEvent(keyCode: KeyCode.a, isDown: true, timestamp: t0))
        #expect(actions == [.startTimer(token: 0, delay: Config.tappingTerm)])
    }

    @Test func oppositeHandRollWithNonHomeRowKey() {
        // A↓ P↓ A↑ P↑ → "ap": releasing A first makes it a letter.
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.p, at: t0 + 0.050)
        h.up(KeyCode.a, at: t0 + 0.100)
        h.up(KeyCode.p, at: t0 + 0.150)
        #expect(h.actions == tap(KeyCode.a) + [press(KeyCode.p), .passThrough])
    }

    @Test func autorepeatOfPendingKeyIsSwallowed() {
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.repeatDown(KeyCode.a, at: t0 + 0.050)
        h.up(KeyCode.a, at: t0 + 0.100)
        #expect(h.actions == tap(KeyCode.a))
    }

    @Test func autorepeatOfHeldModifierIsSwallowed() {
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.advance(to: t0 + 0.250)
        h.repeatDown(KeyCode.a, at: t0 + 0.300)
        h.repeatDown(KeyCode.a, at: t0 + 0.350)
        h.up(KeyCode.a, at: t0 + 0.400)
        #expect(h.actions == [.modifier(.leftShift, down: true), .modifier(.leftShift, down: false)])
    }

    @Test func autorepeatOfOrdinaryKeyPassesThrough() {
        var h = EngineHarness()
        h.down(KeyCode.x, at: t0)
        h.repeatDown(KeyCode.x, at: t0 + 0.500)
        h.up(KeyCode.x, at: t0 + 0.550)
        #expect(h.actions == [.passThrough, .passThrough, .passThrough])
    }

    @Test func emptyKeyMapLeavesEveryKeyAlone() {
        // The "None" layout: home-row keys type and repeat like any other key.
        var h = EngineHarness(settings: .init(keyMap: Layout.none.homeRowMods))
        h.down(KeyCode.a, at: t0)
        h.repeatDown(KeyCode.a, at: t0 + 0.500)
        h.repeatDown(KeyCode.a, at: t0 + 0.550)
        h.up(KeyCode.a, at: t0 + 0.600)
        #expect(h.actions == [.passThrough, .passThrough, .passThrough, .passThrough])
        #expect(h.timers.isEmpty)
    }

    @Test func ordinaryKeyHeldAfterHomeRowTapRepeats() {
        // A↓ P↓ A↑, P held: "a", then P goes down and keeps repeating.
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.p, at: t0 + 0.050)
        h.up(KeyCode.a, at: t0 + 0.100)
        h.repeatDown(KeyCode.p, at: t0 + 0.600)
        h.repeatDown(KeyCode.p, at: t0 + 0.650)
        h.up(KeyCode.p, at: t0 + 0.700)
        #expect(h.actions == tap(KeyCode.a) + [press(KeyCode.p), .passThrough, .passThrough, .passThrough])
    }

    @Test func repeatsWhilePendingAreReplayedInOrder() {
        // A↓ P↓ P(repeat) P↑ A↑ → Shift, then P's events in the order they happened.
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.p, at: t0 + 0.050)
        h.repeatDown(KeyCode.p, at: t0 + 0.100)
        h.up(KeyCode.p, at: t0 + 0.150)
        h.up(KeyCode.a, at: t0 + 0.180)
        #expect(h.actions == [
            .modifier(.leftShift, down: true),
            press(KeyCode.p),
            .key(KeyCode.p, down: true, isRepeat: true),
            release(KeyCode.p),
            .modifier(.leftShift, down: false),
        ])
    }

    @Test func staleTimerIsIgnored() {
        // A was already a tap when its timer fires: nothing more happens.
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        h.up(KeyCode.a, at: t0 + 0.100)
        h.advance(to: t0 + 1)
        #expect(h.actions == tap(KeyCode.a))
    }

    @Test func resetDropsPendingKey() {
        var h = EngineHarness()
        h.down(KeyCode.a, at: t0)
        #expect(h.engine.reset().isEmpty, "a pending key holds no modifier yet")
        h.up(KeyCode.a, at: t0 + 0.100)
        h.advance(to: t0 + 1)
        #expect(h.actions == [.passThrough])
        #expect(h.engine.activeModifiers.isEmpty)
    }

    @Test func typingSpeedRuleIsOffWhenPriorIdleIsZero() {
        // Same keys as `typingSpeedRuleTapsOnNextKey`, but with the rule off the
        // permissive hold applies: X, then Control+J.
        var h = EngineHarness(settings: .init(priorIdle: 0))
        h.down(KeyCode.x, at: t0)
        h.up(KeyCode.x, at: t0 + 0.050)
        h.down(KeyCode.s, at: t0 + 0.100)
        h.down(KeyCode.j, at: t0 + 0.150)
        h.up(KeyCode.j, at: t0 + 0.200)
        h.up(KeyCode.s, at: t0 + 0.250)
        #expect(h.actions == [.passThrough, .passThrough, .modifier(.leftControl, down: true)]
            + tap(KeyCode.j) + [.modifier(.leftControl, down: false)])
    }

    @Test(arguments: Config.homeRowMods.map { ($0.key, $0.value) })
    func everyDefaultHomeRowKeyHoldsItsModifier(keyCode: UInt16, modifiers: ModifierSet) throws {
        let modifier = try #require(modifiers.modifiers.first)
        var h = EngineHarness()
        h.down(keyCode, at: t0)
        h.advance(to: t0 + 0.250)
        h.up(keyCode, at: t0 + 0.300)
        #expect(h.actions == [.modifier(modifier, down: true), .modifier(modifier, down: false)])
    }
}
