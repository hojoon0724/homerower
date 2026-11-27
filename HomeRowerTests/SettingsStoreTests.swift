import Foundation
import Testing
@testable import HomeRower

/// Saved settings, each test in its own throwaway `UserDefaults` suite.
@MainActor
final class SettingsStoreTests {
    private let suiteName = "HomeRowerTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let store: SettingsStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        store = SettingsStore(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func usesDefaultsWhenNothingIsSaved() {
        #expect(store.tappingTermMs == Config.tappingTerm * 1000)
        #expect(store.priorIdleMs == Config.priorIdle * 1000)
        #expect(store.layout == .default)
        #expect(store.savedLayouts.isEmpty)
        #expect(!store.opensSettingsAtLaunch)
        #expect(!store.didApplyLaunchAtLoginDefault)
    }

    @Test func savesValues() {
        store.tappingTermMs = 250
        store.priorIdleMs = 0
        let layer = Layer(name: "Nav", activationKey: KeyCode.space, remaps: [KeyCode.h: 123])
        let layout = Layout(
            homeRowMods: [KeyCode.g: .leftCommand],
            remaps: [KeyCode.capsLock: KeyCode.escape],
            layers: [layer]
        )
        store.layout = layout
        store.opensSettingsAtLaunch = true

        // A second store on the same defaults sees them, like the next launch would.
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.tappingTermMs == 250)
        #expect(reloaded.priorIdleMs == 0)
        #expect(reloaded.layout == layout)
        #expect(reloaded.opensSettingsAtLaunch)
    }

    @Test func noneLayoutStaysEmpty() {
        // Clearing every hold modifier is a choice, not a reason to bring the defaults back.
        store.layout = .none
        #expect(store.layout == .none)
    }

    @Test func migratesSettingsSavedBeforeLayouts() {
        defaults.set(["0": "leftShift", "x": "leftShift", "1": "hyper"], forKey: "keyMap")
        defaults.set(Int(KeyCode.escape), forKey: "capsLockTarget")
        #expect(store.layout == Layout(
            homeRowMods: [KeyCode.a: .leftShift],
            remaps: [KeyCode.capsLock: KeyCode.escape]
        ))

        // The first save replaces the old keys.
        store.layout = .default
        #expect(defaults.object(forKey: "keyMap") == nil)
        #expect(defaults.object(forKey: "capsLockTarget") == nil)
        #expect(store.layout == .default)
    }

    @Test func outOfRangeLegacyCapsLockTargetIsIgnored() {
        defaults.set(-1, forKey: "capsLockTarget")
        #expect(store.layout.capsLockTarget == nil)
    }

    @Test func unreadableLayoutEntriesAreDropped() throws {
        let json = #"{"homeRowMods": {"0": "leftShift", "x": "leftShift", "1": "hyper"}, "remaps": {"57": -1}}"#
        defaults.set(Data(json.utf8), forKey: "layout")
        #expect(store.layout == Layout(homeRowMods: [KeyCode.a: .leftShift]))
    }

    @Test func modifierCombinationsRoundTrip() {
        let layout = Layout(homeRowMods: [KeyCode.f: [.leftOption, .leftCommand], KeyCode.j: .rightCommand])
        store.layout = layout
        #expect(SettingsStore(defaults: defaults).layout == layout)
    }

    @Test func capsLockIsEitherRemappedOrHeldNotBoth() {
        let remapped = LayoutEdit.capsLockTarget(KeyCode.escape).applied(to: .default)
        let held = LayoutEdit.capsLockModifiers(.leftControl).applied(to: remapped)
        #expect(held.capsLockTarget == nil)
        #expect(held.capsLockModifiers == .leftControl)
        #expect(held.capsLockSystemTarget == Config.capsLockStandIn)

        let remappedAgain = LayoutEdit.capsLockTarget(KeyCode.escape).applied(to: held)
        #expect(remappedAgain.capsLockModifiers.isEmpty)
        #expect(remappedAgain.capsLockSystemTarget == KeyCode.escape)

        let normal = LayoutEdit.capsLockModifiers([]).applied(to: held)
        #expect(normal.capsLockSystemTarget == nil)
        #expect(normal == .default)
    }

    @Test func forgettingPromptsClearsEveryPermission() {
        for permission in Permission.allCases {
            store.setHasPrompted(true, for: permission)
            #expect(store.hasPrompted(for: permission))
        }
        store.forgetPermissionPrompts()
        for permission in Permission.allCases {
            #expect(!store.hasPrompted(for: permission))
        }
    }

    /// Settings changed in the UI go through `EventTap` and must end up saved.
    @Test func eventTapLoadsAndSavesThroughTheStore() {
        store.tappingTermMs = 300
        let eventTap = EventTap(store: store)
        #expect(eventTap.tappingTermMs == 300)

        eventTap.priorIdleMs = 120
        eventTap.setModifiers([], for: KeyCode.a)
        #expect(store.priorIdleMs == 120)
        #expect(store.layout.homeRowMods[KeyCode.a] == nil)

        eventTap.resetTimingsToDefaults()
        eventTap.select(.preset(.none))
        #expect(store.tappingTermMs == Config.tappingTerm * 1000)
        #expect(store.layout == .none)
    }
}
