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

    // MARK: - Layers

    @Test func addedLayersPassThroughAndAreInOrder() {
        let eventTap = EventTap(store: store)
        let first = eventTap.addLayer()
        let second = eventTap.addLayer()
        #expect(eventTap.layoutSelection == .custom)
        #expect(eventTap.layout.layers.map(\.id) == [first, second])
        #expect(eventTap.layout.layers.allSatisfy { $0.remaps.isEmpty && $0.activationKeys.isEmpty })
        // Layer 0 is untouched.
        #expect(eventTap.layout.homeRowMods == Layout.default.homeRowMods)
    }

    @Test func remappingAKeyOnALayer() throws {
        let eventTap = EventTap(store: store)
        let id = try #require(eventTap.addLayer())
        eventTap.setRemap(KeyStroke(KeyCode.escape), for: KeyCode.h, inLayer: id)
        #expect(eventTap.layout.layers.first?.remaps == [KeyCode.h: KeyStroke(KeyCode.escape)])

        // Acting as itself is the same as passing through.
        eventTap.setRemap(KeyStroke(KeyCode.h), for: KeyCode.h, inLayer: id)
        #expect(eventTap.layout.layers.first?.remaps.isEmpty == true)
    }

    @Test func layersAreSavedWithTheLayout() throws {
        let eventTap = EventTap(store: store)
        let id = try #require(eventTap.addLayer())
        eventTap.setRemap(KeyStroke(KeyCode.escape), for: KeyCode.h, inLayer: id)
        eventTap.saveCurrentLayout(as: .newLayout(name: "Nav"))

        let saved = try #require(eventTap.savedLayouts.first)
        #expect(saved.layout.layers.map(\.id) == [id])
        #expect(saved.layout.layers.first?.remaps == [KeyCode.h: KeyStroke(KeyCode.escape)])

        // Switching away and back brings the layers back, across launches too.
        let relaunched = EventTap(store: store)
        relaunched.select(.preset(.none))
        #expect(relaunched.layout.layers.isEmpty)
        relaunched.select(.saved(saved.id))
        #expect(relaunched.layout.layers == saved.layout.layers)
    }

    @Test func layersStopAtTheMost() {
        let eventTap = EventTap(store: store)
        for _ in 1..<Layout.maxLayerCount {
            #expect(eventTap.addLayer() != nil)
        }
        #expect(!eventTap.layout.canAddLayer)
        #expect(eventTap.addLayer() == nil)
        #expect(eventTap.layout.layers.count == Layout.maxLayerCount - 1)
    }

    @Test func deletingALayerMovesTheLaterOnesUpWithTheirRemaps() throws {
        let eventTap = EventTap(store: store)
        let ids = (0..<4).compactMap { _ in eventTap.addLayer() }
        eventTap.setRemap(KeyStroke(KeyCode.escape), for: KeyCode.h, inLayer: ids[2])
        eventTap.setRemap(KeyStroke(KeyCode.a), for: KeyCode.j, inLayer: ids[3])

        // Deleting Layer 2: Layers 3 and 4 become 2 and 3.
        eventTap.deleteLayer(id: ids[1])
        let layers = eventTap.layout.layers
        #expect(layers.map(\.id) == [ids[0], ids[2], ids[3]])
        #expect(layers[1].remaps == [KeyCode.h: KeyStroke(KeyCode.escape)])
        #expect(layers[2].remaps == [KeyCode.j: KeyStroke(KeyCode.a)])
        #expect(eventTap.layout.canAddLayer)
    }

    @Test func keysPassThroughToLayer0UnlessTheLayerRemapsThem() {
        var layout = Layout()
        layout.capsLockTarget = KeyCode.escape
        let layer = Layer(remaps: [KeyCode.h: KeyStroke(123)])
        let other = Layer(remaps: [KeyCode.capsLock: KeyStroke(KeyCode.delete)])
        layout.layers = [layer, other]

        // Caps Lock stays Esc on a layer that doesn't give it a key...
        #expect(layout.key(for: KeyCode.capsLock, inLayer: nil) == KeyStroke(KeyCode.escape))
        #expect(layout.key(for: KeyCode.capsLock, inLayer: layer.id) == KeyStroke(KeyCode.escape))
        // ...and acts as Backspace only on the layer that does.
        #expect(layout.key(for: KeyCode.capsLock, inLayer: other.id) == KeyStroke(KeyCode.delete))
        #expect(layout.key(for: KeyCode.h, inLayer: layer.id) == KeyStroke(123))
        #expect(layout.key(for: KeyCode.h, inLayer: other.id) == KeyStroke(KeyCode.h))
    }

    @Test func aLayerKeyCantHoldModifiersToo() throws {
        let eventTap = EventTap(store: store)
        let first = try #require(eventTap.addLayer())
        let second = try #require(eventTap.addLayer())

        // F holds ⌘ by default; switching a layer drops that.
        eventTap.setLayerKey(first, for: KeyCode.f)
        #expect(eventTap.layout.homeRowMods[KeyCode.f] == nil)
        #expect(eventTap.layout.layerNumber(activatedBy: KeyCode.f) == 1)

        // Giving it modifiers again stops it switching.
        eventTap.setModifiers(.leftShift, for: KeyCode.f)
        #expect(eventTap.layout.layerNumber(activatedBy: KeyCode.f) == nil)

        // One layer per key, but a layer can have several keys.
        eventTap.setLayerKey(first, for: KeyCode.g)
        eventTap.setLayerKey(second, for: KeyCode.g)
        #expect(eventTap.layout.layerNumber(activatedBy: KeyCode.g) == 2)
        #expect(eventTap.layout.layers[0].activationKeys.isEmpty)
        eventTap.setLayerKey(second, for: KeyCode.h)
        #expect(eventTap.layout.layerNumber(activatedBy: KeyCode.g) == 2)
        #expect(eventTap.layout.layerNumber(activatedBy: KeyCode.h) == 2)
        eventTap.setLayerKey(nil, for: KeyCode.g)
        #expect(eventTap.layout.layers[1].activationKeys == [KeyCode.h])
    }

    @Test func aLayersOwnKeyCantBeRemappedOnIt() throws {
        let eventTap = EventTap(store: store)
        let id = try #require(eventTap.addLayer())
        eventTap.setRemap(KeyStroke(KeyCode.escape), for: KeyCode.g, inLayer: id)
        // Making G the layer key drops its remap there, and it can't get another.
        eventTap.setLayerKey(id, for: KeyCode.g)
        #expect(eventTap.layout.layers[0].remaps.isEmpty)
        eventTap.setRemap(KeyStroke(KeyCode.escape), for: KeyCode.g, inLayer: id)
        #expect(eventTap.layout.layers[0].remaps.isEmpty)
    }

    @Test func layerKeysMoveWithTheirLayersWhenOneIsDeleted() throws {
        let eventTap = EventTap(store: store)
        let ids = (0..<3).compactMap { _ in eventTap.addLayer() }
        eventTap.setLayerKey(ids[2], for: KeyCode.g)
        eventTap.deleteLayer(id: ids[0])
        #expect(eventTap.layout.layerNumber(activatedBy: KeyCode.g) == 2)
        eventTap.deleteLayer(id: ids[2])
        #expect(eventTap.layout.layerNumber(activatedBy: KeyCode.g) == nil)
    }
}
