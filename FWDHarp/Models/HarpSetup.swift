import Foundation

/// One AUv3 effect in the chain. Copied from FWD Sequencer (Models.swift) on 2026-11-20,
/// so its saved form is the same as FWD's.
nonisolated struct PluginSlot: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var pluginInfo: PluginInfo
    /// PropertyList-serialised AUv3 state, exactly as for an instrument.
    var stateData: Data? = nil
    /// Optional so slots saved before bypass existed still decode; nil means active.
    var isBypassed: Bool? = nil

    var bypassed: Bool { isBypassed == true }

    init(id: UUID = UUID(), pluginInfo: PluginInfo, stateData: Data? = nil,
         isBypassed: Bool? = nil) {
        self.id = id; self.pluginInfo = pluginInfo
        self.stateData = stateData; self.isBypassed = isBypassed
    }

    // Tolerant decoder: the synthesised one throws on a missing key even with a default.
    private enum CodingKeys: String, CodingKey { case id, pluginInfo, stateData, isBypassed }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pluginInfo = try c.decode(PluginInfo.self, forKey: .pluginInfo)
        stateData = try c.decodeIfPresent(Data.self, forKey: .stateData)
        isBypassed = try c.decodeIfPresent(Bool.self, forKey: .isBypassed)
    }
}

/// Everything FWD Harp remembers between launches: the instrument and its sound, the
/// effects after it, and the key. Saved automatically (see SetupStorage).
///
/// Every field is optional or defaulted and the decoder is tolerant, so a file from a
/// later or earlier version still opens: settings it does not know are simply left at
/// their defaults. The chord pads, key, strum and MIDI settings join it as they arrive.
nonisolated struct HarpSetup: Codable, Equatable {
    static let currentFormatVersion = 1
    /// General MIDI program 46, Orchestral Harp: a harp app should sound like one.
    static let defaultBuiltInSound = 46
    /// As in FWD Sequencer.
    static let maximumEffects = 4

    var formatVersion: Int = HarpSetup.currentFormatVersion
    /// The AUv3 instrument, or nil for the built-in General MIDI sound.
    var instrument: PluginInfo? = nil
    /// The instrument's own state (its patch), as AudioEngineManager captures it.
    var instrumentState: Data? = nil
    /// The built-in sound: a General MIDI program, or GeneralMIDI.drumKit.
    var builtInSound: Int = HarpSetup.defaultBuiltInSound
    var effects: [PluginSlot] = []
    /// The whole effects chain switched out. Each effect's own bypass is separate.
    var effectsBypassed: Bool = false
    /// The key the pads play in: its tonic as a pitch class, 0 = C … 11 = B.
    var keyTonic: Int = 0

    var key: MajorKey { MajorKey(tonic: keyTonic) }

    init() {}

    /// Whether the effect at `index` is silent: bypassed itself, or the chain is out.
    func effectIsSilenced(at index: Int) -> Bool {
        effectsBypassed || (effects.indices.contains(index) && effects[index].bypassed)
    }

    /// Put every value in range, so nothing read from a file can upset the engine.
    func normalized() -> HarpSetup {
        var copy = self
        if !(0...GeneralMIDI.drumKit).contains(copy.builtInSound) {
            copy.builtInSound = Self.defaultBuiltInSound
        }
        if copy.effects.count > Self.maximumEffects {
            copy.effects = Array(copy.effects.prefix(Self.maximumEffects))
        }
        // A patch with no instrument to belong to means nothing.
        if copy.instrument == nil { copy.instrumentState = nil }
        if !(0..<12).contains(copy.keyTonic) { copy.keyTonic = 0 }
        copy.formatVersion = Self.currentFormatVersion
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, instrument, instrumentState, builtInSound, effects, effectsBypassed, keyTonic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        instrument = try c.decodeIfPresent(PluginInfo.self, forKey: .instrument)
        instrumentState = try c.decodeIfPresent(Data.self, forKey: .instrumentState)
        builtInSound = try c.decodeIfPresent(Int.self, forKey: .builtInSound) ?? Self.defaultBuiltInSound
        effects = try c.decodeIfPresent([PluginSlot].self, forKey: .effects) ?? []
        effectsBypassed = try c.decodeIfPresent(Bool.self, forKey: .effectsBypassed) ?? false
        keyTonic = try c.decodeIfPresent(Int.self, forKey: .keyTonic) ?? 0
    }
}
