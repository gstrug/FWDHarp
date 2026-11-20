import Foundation

/// An installed AUv3 plugin, by its audio-component identity. Copied from FWD
/// Sequencer (Models.swift) on 2026-11-20.
nonisolated struct PluginInfo: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var manufacturerName: String
    var componentType: UInt32
    var componentSubType: UInt32
    var componentManufacturer: UInt32

    /// Audio-component identity is stable across scans and launches. `id` remains in
    /// the saved format for backward compatibility, but must not decide whether two
    /// records refer to the same installed plugin.
    var componentIdentifier: String {
        "\(componentType)-\(componentSubType)-\(componentManufacturer)"
    }

    static func == (lhs: PluginInfo, rhs: PluginInfo) -> Bool {
        lhs.componentType == rhs.componentType
            && lhs.componentSubType == rhs.componentSubType
            && lhs.componentManufacturer == rhs.componentManufacturer
    }
}
