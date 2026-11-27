import Foundation

/// A layout the user saved under a name, offered next to the built-in presets.
nonisolated struct SavedLayout: Identifiable, Equatable, Sendable, Codable {
    var id = UUID()
    var name: String
    var layout: Layout
}
