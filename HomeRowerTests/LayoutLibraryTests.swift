import Foundation
import Testing
@testable import HomeRower

/// Choosing, editing, saving and managing layouts through `EventTap`, each test with its
/// own throwaway settings. Edits stick to hold modifiers: Caps Lock edits would remap the
/// real keyboard.
@MainActor
final class LayoutLibraryTests {
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

    @Test func firstLaunchHasNoCustom() {
        let eventTap = EventTap(store: store)
        #expect(eventTap.layoutSelection == .preset(.default))
        #expect(eventTap.layout == .default)
        #expect(eventTap.customLayout == nil)
    }

    @Test func editingCopiesTheLayoutIntoCustom() {
        let eventTap = EventTap(store: store)
        eventTap.setModifiers(.leftCommand, for: KeyCode.a)
        #expect(eventTap.layoutSelection == .custom)
        #expect(eventTap.customLayout?.homeRowMods[KeyCode.a] == .leftCommand)
        // The rest of Default comes along.
        #expect(eventTap.customLayout?.homeRowMods[KeyCode.f] == .leftCommand)
        #expect(eventTap.defaultLayout == .default)
    }

    @Test func editMatchingAnotherLayoutIsStillCustom() {
        let eventTap = EventTap(store: store)
        eventTap.select(.preset(.none))
        eventTap.setModifiers(.leftShift, for: KeyCode.a)
        eventTap.setModifiers([], for: KeyCode.a)
        #expect(eventTap.layoutSelection == .custom)
        #expect(eventTap.customLayout == Layout.none)
    }

    @Test func switchingAwayKeepsCustom() {
        let eventTap = EventTap(store: store)
        eventTap.setModifiers([], for: KeyCode.a)
        let custom = eventTap.customLayout

        eventTap.select(.preset(.none))
        #expect(eventTap.layout == .none)
        #expect(eventTap.customLayout == custom)

        // Across launches too.
        let relaunched = EventTap(store: store)
        #expect(relaunched.customLayout == custom)
        relaunched.select(.custom)
        #expect(relaunched.layout == custom)
    }

    @Test func savingCustomMakesItGoAway() throws {
        let eventTap = EventTap(store: store)
        eventTap.setModifiers([], for: KeyCode.a)
        eventTap.saveCurrentLayout(as: .newLayout(name: "user001"))

        let saved = try #require(eventTap.savedLayouts.first)
        #expect(saved.name == "user001")
        #expect(saved.layout.homeRowMods[KeyCode.a] == nil)
        #expect(eventTap.layoutSelection == .saved(saved.id))
        #expect(eventTap.customLayout == nil)
    }

    @Test func editingASavedLayoutLeavesItAlone() throws {
        let eventTap = EventTap(store: store)
        eventTap.setModifiers([], for: KeyCode.a)
        eventTap.saveCurrentLayout(as: .newLayout(name: "user001"))
        let saved = try #require(eventTap.savedLayouts.first)

        eventTap.setModifiers([], for: KeyCode.s)
        #expect(eventTap.layoutSelection == .custom)
        #expect(eventTap.customLayout?.homeRowMods[KeyCode.a] == nil)
        #expect(eventTap.customLayout?.homeRowMods[KeyCode.s] == nil)
        #expect(eventTap.savedLayouts.first == saved)
    }

    @Test func editingInCustomNeverAsks() {
        let eventTap = EventTap(store: store)
        eventTap.setModifiers([], for: KeyCode.a)
        eventTap.setModifiers([], for: KeyCode.s)
        #expect(eventTap.pendingEdit == nil)
        #expect(eventTap.customLayout?.homeRowMods[KeyCode.s] == nil)
    }

    // MARK: - Replacing Custom

    /// Custom holds an edit of Default, and None is in use.
    private func eventTapWithCustomAwayFromIt() -> EventTap {
        let eventTap = EventTap(store: store)
        eventTap.setModifiers([], for: KeyCode.a)
        eventTap.select(.preset(.none))
        return eventTap
    }

    @Test func editingAnotherLayoutWaitsForTheUser() {
        let eventTap = eventTapWithCustomAwayFromIt()
        let custom = eventTap.customLayout
        eventTap.setModifiers(.leftCommand, for: KeyCode.j)
        #expect(eventTap.pendingEdit == .modifier(.leftCommand, keyCode: KeyCode.j))
        #expect(eventTap.layout == .none)
        #expect(eventTap.customLayout == custom)
    }

    @Test func cancelDropsTheEdit() {
        let eventTap = eventTapWithCustomAwayFromIt()
        let custom = eventTap.customLayout
        eventTap.setModifiers(.leftCommand, for: KeyCode.j)
        eventTap.cancelPendingEdit()
        #expect(eventTap.pendingEdit == nil)
        #expect(eventTap.layoutSelection == .preset(.none))
        #expect(eventTap.layout == .none)
        #expect(eventTap.customLayout == custom)
    }

    @Test func replaceStartsANewCustom() {
        let eventTap = eventTapWithCustomAwayFromIt()
        eventTap.setModifiers(.leftCommand, for: KeyCode.j)
        eventTap.confirmPendingEdit()
        #expect(eventTap.layoutSelection == .custom)
        #expect(eventTap.customLayout == Layout(homeRowMods: [KeyCode.j: .leftCommand]))
        #expect(eventTap.layout == eventTap.customLayout)
    }

    @Test func saveCustomKeepsTheOldOneThenStartsANewCustom() throws {
        let eventTap = eventTapWithCustomAwayFromIt()
        let oldCustom = try #require(eventTap.customLayout)
        eventTap.setModifiers(.leftCommand, for: KeyCode.j)
        eventTap.saveCustomLayout(as: .newLayout(name: "user001"))

        #expect(eventTap.savedLayouts.map(\.name) == ["user001"])
        #expect(eventTap.savedLayouts.first?.layout == oldCustom)
        #expect(eventTap.pendingEdit == nil)
        #expect(eventTap.layoutSelection == .custom)
        #expect(eventTap.customLayout == Layout(homeRowMods: [KeyCode.j: .leftCommand]))
    }

    // MARK: - Updating and managing

    @Test func savingOverASavedLayoutUpdatesIt() throws {
        let eventTap = EventTap(store: store)
        eventTap.setModifiers([], for: KeyCode.a)
        eventTap.saveCurrentLayout(as: .newLayout(name: "user001"))
        let id = try #require(eventTap.savedLayouts.first?.id)

        eventTap.setModifiers([], for: KeyCode.s)
        eventTap.saveCurrentLayout(as: .saved(id))
        #expect(eventTap.savedLayouts.count == 1)
        #expect(eventTap.savedLayouts.first?.layout.homeRowMods[KeyCode.s] == nil)
        #expect(eventTap.layoutSelection == .saved(id))
        #expect(eventTap.customLayout == nil)
    }

    @Test func userCanReplaceAndRestoreDefault() {
        let eventTap = EventTap(store: store)
        eventTap.setModifiers([], for: KeyCode.a)
        eventTap.saveCurrentLayout(as: .default)
        #expect(eventTap.layoutSelection == .preset(.default))
        #expect(EventTap(store: store).defaultLayout.homeRowMods[KeyCode.a] == nil)

        eventTap.restoreDefaultLayout()
        #expect(eventTap.defaultLayout == .default)
        #expect(eventTap.layout == .default)
    }

    @Test func reservedAndTakenNamesAreRejected() {
        let eventTap = EventTap(store: store)
        eventTap.saveCurrentLayout(as: .newLayout(name: "user001"))
        for name in ["", "  ", "None", "default", "Custom", "USER001"] {
            #expect(!eventTap.isNameAvailable(name), "\(name)")
        }
        #expect(eventTap.isNameAvailable("user002"))
    }

    @Test func discardingCustomInUseGoesBackToWhereItStarted() {
        let eventTap = EventTap(store: store)
        eventTap.select(.preset(.none))
        eventTap.setModifiers(.leftShift, for: KeyCode.a)
        eventTap.discardCustomLayout()
        #expect(eventTap.customLayout == nil)
        #expect(eventTap.layoutSelection == .preset(.none))
        #expect(eventTap.layout == .none)
    }

    @Test func deletingTheLayoutInUseSwitchesToDefault() throws {
        let eventTap = EventTap(store: store)
        eventTap.select(.preset(.none))
        eventTap.saveCurrentLayout(as: .newLayout(name: "Blank"))
        let id = try #require(eventTap.savedLayouts.first?.id)

        eventTap.deleteLayout(id: id)
        #expect(eventTap.savedLayouts.isEmpty)
        #expect(eventTap.layoutSelection == .preset(.default))
        #expect(eventTap.layout == .default)
    }
}
