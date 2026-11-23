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

/// Everything FWD Harp remembers between launches: each part's instrument, sound and
/// effects, the mixer, the key, the plate's range, octave, order and scale, and
/// auto-strum's pattern and tempo. Saved automatically (see SetupStorage).
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

    /// A minor key (Graham, 2026-11-23); old setups open in the major key they had.
    var keyMinor = false
    var key: MusicKey { MusicKey(tonic: keyTonic, minor: keyMinor) }
    /// How many strings the plate has (StrumPlate.stringChoices), whatever it plays.
    var plateStrings: Int = StrumPlate.defaultStrings
    /// The plate moved up or down by whole octaves (StrumPlate.octaveShiftRange).
    var octaveShift: Int = 0
    /// Auto-strum's pattern and speed. Whether it is on is not saved: it starts off.
    /// New setups start on Style, the rhythm style's own harp part (2026-11-23).
    var autoStrumPattern: AutoStrumPattern = .style
    /// The order of the notes up the plate for hand strumming.
    var platePattern: PlatePattern = .straight
    /// What the plate plays: the chord held, or a scale in the key.
    var plateScale: PlateScale = .chord
    /// How long plate notes sound.
    var plateRing: PlateRing = .whileHeld
    var tempo: Double = AutoStrum.defaultTempo
    /// Auto-strum's own sound, or nil to play through the plate's instrument (the
    /// default, so nothing changes until one is chosen, and a heavy plugin is not
    /// loaded twice). The plate's sound is the fields above, as before, so a setup
    /// saved before parts existed opens unchanged.
    var autoSound: PartSound? = nil
    var plateMix = ChannelMix()
    var autoMix = ChannelMix()
    /// The rhythm section's sounds: the built-in drum kit and a finger bass to start
    /// (design brief), each with its own instrument, effects and channel.
    var drumsSound = PartSound(builtInSound: GeneralMIDI.drumKit)
    var bassSound = PartSound(builtInSound: PartSound.defaultBassBuiltInSound)
    var drumsMix = ChannelMix()
    var bassMix = ChannelMix()
    var masterVolume: Float = 1
    var midiOut = MIDIOutSettings()
    /// The rhythm section's style and A or B. Whether it is running, SYNC and INTRO
    /// are not saved: it always opens stopped, with no intro chosen.
    var rhythmStyle: RhythmStyle = .rock
    var rhythmVariation: RhythmVariation = .a

    init() {}

    /// The plate's sound, gathered from (and written back to) its fields.
    var plateSound: PartSound {
        get {
            PartSound(instrument: instrument, instrumentState: instrumentState, builtInSound: builtInSound,
                      effects: effects, effectsBypassed: effectsBypassed)
        }
        set {
            instrument = newValue.instrument
            instrumentState = newValue.instrumentState
            builtInSound = newValue.builtInSound
            effects = newValue.effects
            effectsBypassed = newValue.effectsBypassed
        }
    }

    /// A part's own sound; nil for auto-strum when it plays through the plate's.
    func sound(of part: HarpPart) -> PartSound? {
        switch part {
        case .plate: return plateSound
        case .auto: return autoSound
        case .drums: return drumsSound
        case .bass: return bassSound
        }
    }

    mutating func setSound(_ sound: PartSound, for part: HarpPart) {
        switch part {
        case .plate: plateSound = sound
        case .auto: autoSound = sound
        case .drums: drumsSound = sound
        case .bass: bassSound = sound
        }
    }

    func mix(of part: HarpPart) -> ChannelMix {
        switch part {
        case .plate: return plateMix
        case .auto: return autoMix
        case .drums: return drumsMix
        case .bass: return bassMix
        }
    }

    mutating func setMix(_ mix: ChannelMix, for part: HarpPart) {
        switch part {
        case .plate: plateMix = mix
        case .auto: autoMix = mix
        case .drums: drumsMix = mix
        case .bass: bassMix = mix
        }
    }

    /// Whether the effect at `index` is silent: bypassed itself, or the chain is out.
    func effectIsSilenced(at index: Int) -> Bool {
        effectsBypassed || (effects.indices.contains(index) && effects[index].bypassed)
    }

    /// Put every value in range, so nothing read from a file can upset the engine.
    func normalized() -> HarpSetup {
        var copy = self
        if !(0..<12).contains(copy.keyTonic) { copy.keyTonic = 0 }
        if !StrumPlate.stringChoices.contains(copy.plateStrings) {
            // The nearest choice, so a count from a later version still lands sensibly.
            copy.plateStrings = StrumPlate.stringChoices.min { abs($0 - copy.plateStrings) < abs($1 - copy.plateStrings) }
                ?? StrumPlate.defaultStrings
        }
        if !StrumPlate.octaveShiftRange.contains(copy.octaveShift) { copy.octaveShift = 0 }
        if !AutoStrum.tempoRange.contains(copy.tempo) || !copy.tempo.isFinite { copy.tempo = AutoStrum.defaultTempo }
        copy.plateSound = copy.plateSound.normalized()
        copy.autoSound = copy.autoSound?.normalized()
        copy.plateMix = copy.plateMix.normalized()
        copy.autoMix = copy.autoMix.normalized()
        copy.drumsSound = copy.drumsSound.normalized()
        copy.bassSound = copy.bassSound.normalized()
        copy.drumsMix = copy.drumsMix.normalized()
        copy.bassMix = copy.bassMix.normalized()
        copy.masterVolume = ChannelMix.clampVolume(copy.masterVolume, default: 1)
        copy.midiOut = copy.midiOut.normalized()
        copy.formatVersion = Self.currentFormatVersion
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, instrument, instrumentState, builtInSound, effects, effectsBypassed, keyTonic, keyMinor
        case plateStrings, octaveShift, autoStrumPattern, tempo, platePattern, plateScale
        case autoSound, plateMix, autoMix, masterVolume, plateRing, midiOut
        case drumsSound, bassSound, drumsMix, bassMix, rhythmStyle, rhythmVariation
    }

    /// Read from older files, never written.
    private enum LegacyKeys: String, CodingKey { case plateOctaves }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        instrument = try c.decodeIfPresent(PluginInfo.self, forKey: .instrument)
        instrumentState = try c.decodeIfPresent(Data.self, forKey: .instrumentState)
        builtInSound = try c.decodeIfPresent(Int.self, forKey: .builtInSound) ?? Self.defaultBuiltInSound
        effects = try c.decodeIfPresent([PluginSlot].self, forKey: .effects) ?? []
        effectsBypassed = try c.decodeIfPresent(Bool.self, forKey: .effectsBypassed) ?? false
        keyTonic = try c.decodeIfPresent(Int.self, forKey: .keyTonic) ?? 0
        keyMinor = try c.decodeIfPresent(Bool.self, forKey: .keyMinor) ?? false
        // A setup saved with the old RANGE in octaves keeps the same strings it had.
        if let strings = try c.decodeIfPresent(Int.self, forKey: .plateStrings) {
            plateStrings = strings
        } else if let octaves = try decoder.container(keyedBy: LegacyKeys.self)
                    .decodeIfPresent(Int.self, forKey: .plateOctaves) {
            plateStrings = StrumPlate.strings(forOldOctaves: octaves)
        } else {
            plateStrings = StrumPlate.defaultStrings
        }
        octaveShift = try c.decodeIfPresent(Int.self, forKey: .octaveShift) ?? 0
        // A pattern this version does not know (from a later one) falls back.
        autoStrumPattern = (try? c.decodeIfPresent(AutoStrumPattern.self, forKey: .autoStrumPattern)) ?? .arpeggioUp
        tempo = try c.decodeIfPresent(Double.self, forKey: .tempo) ?? AutoStrum.defaultTempo
        platePattern = (try? c.decodeIfPresent(PlatePattern.self, forKey: .platePattern)) ?? .straight
        plateScale = (try? c.decodeIfPresent(PlateScale.self, forKey: .plateScale)) ?? .chord
        plateRing = (try? c.decodeIfPresent(PlateRing.self, forKey: .plateRing)) ?? .whileHeld
        autoSound = try c.decodeIfPresent(PartSound.self, forKey: .autoSound)
        plateMix = try c.decodeIfPresent(ChannelMix.self, forKey: .plateMix) ?? ChannelMix()
        autoMix = try c.decodeIfPresent(ChannelMix.self, forKey: .autoMix) ?? ChannelMix()
        masterVolume = try c.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1
        midiOut = try c.decodeIfPresent(MIDIOutSettings.self, forKey: .midiOut) ?? MIDIOutSettings()
        drumsSound = try c.decodeIfPresent(PartSound.self, forKey: .drumsSound)
            ?? PartSound(builtInSound: GeneralMIDI.drumKit)
        bassSound = try c.decodeIfPresent(PartSound.self, forKey: .bassSound)
            ?? PartSound(builtInSound: PartSound.defaultBassBuiltInSound)
        drumsMix = try c.decodeIfPresent(ChannelMix.self, forKey: .drumsMix) ?? ChannelMix()
        bassMix = try c.decodeIfPresent(ChannelMix.self, forKey: .bassMix) ?? ChannelMix()
        rhythmStyle = (try? c.decodeIfPresent(RhythmStyle.self, forKey: .rhythmStyle)) ?? .rock
        rhythmVariation = (try? c.decodeIfPresent(RhythmVariation.self, forKey: .rhythmVariation)) ?? .a
    }
}

/// The parts that make sound, each with its own instrument, effects and mixer
/// channel: the plate, auto-strum, and the rhythm section's drums and bass.
nonisolated enum HarpPart: String, CaseIterable, Codable {
    case plate, auto, drums, bass

    var title: String {
        switch self {
        case .plate: return "Plate"
        case .auto: return "Auto-Strum"
        case .drums: return "Drums"
        case .bass: return "Bass"
        }
    }
}

/// One part's sound: its instrument (an AUv3 or the built-in General MIDI sound) and
/// the effects after it.
nonisolated struct PartSound: Codable, Equatable {
    /// A built-in sound for auto-strum when it is first given its own: nylon guitar,
    /// to accompany the harp.
    static let defaultAutoBuiltInSound = 24
    /// General MIDI 33, Electric Bass (finger), for the rhythm section's bass.
    static let defaultBassBuiltInSound = 33

    var instrument: PluginInfo? = nil
    var instrumentState: Data? = nil
    var builtInSound: Int = HarpSetup.defaultBuiltInSound
    var effects: [PluginSlot] = []
    var effectsBypassed: Bool = false

    init(instrument: PluginInfo? = nil, instrumentState: Data? = nil,
         builtInSound: Int = HarpSetup.defaultBuiltInSound,
         effects: [PluginSlot] = [], effectsBypassed: Bool = false) {
        self.instrument = instrument
        self.instrumentState = instrumentState
        self.builtInSound = builtInSound
        self.effects = effects
        self.effectsBypassed = effectsBypassed
    }

    func effectIsSilenced(at index: Int) -> Bool {
        effectsBypassed || (effects.indices.contains(index) && effects[index].bypassed)
    }

    func normalized() -> PartSound {
        var copy = self
        if !(0...GeneralMIDI.drumKit).contains(copy.builtInSound) {
            copy.builtInSound = HarpSetup.defaultBuiltInSound
        }
        if copy.effects.count > HarpSetup.maximumEffects {
            copy.effects = Array(copy.effects.prefix(HarpSetup.maximumEffects))
        }
        // A patch with no instrument to belong to means nothing.
        if copy.instrument == nil { copy.instrumentState = nil }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case instrument, instrumentState, builtInSound, effects, effectsBypassed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instrument = try c.decodeIfPresent(PluginInfo.self, forKey: .instrument)
        instrumentState = try c.decodeIfPresent(Data.self, forKey: .instrumentState)
        builtInSound = try c.decodeIfPresent(Int.self, forKey: .builtInSound) ?? HarpSetup.defaultBuiltInSound
        effects = try c.decodeIfPresent([PluginSlot].self, forKey: .effects) ?? []
        effectsBypassed = try c.decodeIfPresent(Bool.self, forKey: .effectsBypassed) ?? false
    }
}

/// A part's mixer channel. Volume is linear gain, as in FWD's mixer (the fader shows
/// dB); pan runs -1 (left) to 1 (right).
nonisolated struct ChannelMix: Codable, Equatable {
    static let maximumVolume: Float = 2   // +6 dB, FWD's fader top
    var volume: Float = 0.8
    var pan: Float = 0
    var muted: Bool = false

    init(volume: Float = 0.8, pan: Float = 0, muted: Bool = false) {
        self.volume = volume; self.pan = pan; self.muted = muted
    }

    /// What the engine is given: silent while muted.
    var effectiveVolume: Float { muted ? 0 : volume }

    static func clampVolume(_ volume: Float, default fallback: Float) -> Float {
        volume.isFinite ? min(max(volume, 0), maximumVolume) : fallback
    }

    func normalized() -> ChannelMix {
        ChannelMix(volume: Self.clampVolume(volume, default: 0.8),
                   pan: pan.isFinite ? min(max(pan, -1), 1) : 0,
                   muted: muted)
    }

    private enum CodingKeys: String, CodingKey { case volume, pan, muted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? 0.8
        pan = try c.decodeIfPresent(Float.self, forKey: .pan) ?? 0
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }
}
