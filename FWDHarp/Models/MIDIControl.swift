import Foundation

// MARK: - MIDI control: links from a controller's knobs, faders and buttons to the app
//
// Copied from FWD Sequencer (Models/MIDIControl.swift) on 2026-11-22, with the harp's own
// targets: the portable half of MIDI Learn. What a link is, what it can control, how an
// incoming message is matched and scaled, and the built-in templates. No CoreMIDI and no
// UI, so it is tested with the rest of the core. The app half (applying actions, the
// Learn mode UI) is MIDIControlCenter. FWD's key routing to tracks is left out: here a
// controller's keys play the plate's instrument, as before.
//
// Links are APP-WIDE, as in FWD: a controller set up once works the same every time.

/// What a link controls.
nonisolated enum MIDIControlTarget: Codable, Hashable {
    /// A chord pad or modifier: held while the button or key is down, like a finger.
    case pad(ChordPad)
    case hold, autoStrum, tapTempo, panic
    case tempo
    case octaveUp, octaveDown, autoOctaveUp, autoOctaveDown
    // The rhythm section.
    case rhythmStartStop, rhythmStop, rhythmSync, fill, introOutro, variationA, variationB
    case previousStyle, nextStyle
    // The mixer.
    case masterVolume
    case partVolume(HarpPart), partPan(HarpPart), partMute(HarpPart), partSolo(HarpPart), partEffects(HarpPart)

    /// Continuous targets take the knob or fader's position; the rest act on a press.
    var isContinuous: Bool {
        switch self {
        case .tempo, .masterVolume, .partVolume, .partPan: return true
        default: return false
        }
    }

    /// Pads are held, so they hear the release too; other buttons act on the press.
    var hearsRelease: Bool {
        if case .pad = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .pad(let pad):         return pad.isModifier ? "\(pad.modifierTitle ?? "") Pad" : "Pad \(pad.degreeLabel)"
        case .hold:                 return "Hold"
        case .autoStrum:            return "Auto-Strum On/Off"
        case .tapTempo:             return "Tap Tempo"
        case .panic:                return "Panic"
        case .tempo:                return "Tempo"
        case .octaveUp:             return "Plate Octave Up"
        case .octaveDown:           return "Plate Octave Down"
        case .autoOctaveUp:         return "Auto-Strum Octave Up"
        case .autoOctaveDown:       return "Auto-Strum Octave Down"
        case .rhythmStartStop:      return "Drums Start / Stop"
        case .rhythmStop:           return "Drums Stop"
        case .rhythmSync:           return "Drums Sync"
        case .fill:                 return "Fill"
        case .introOutro:           return "Intro / Outro"
        case .variationA:           return "Variation A"
        case .variationB:           return "Variation B"
        case .previousStyle:        return "Previous Style"
        case .nextStyle:            return "Next Style"
        case .masterVolume:         return "Master Volume"
        case .partVolume(let p):    return "\(p.title) Volume"
        case .partPan(let p):       return "\(p.title) Pan"
        case .partMute(let p):      return "\(p.title) Mute"
        case .partSolo(let p):      return "\(p.title) Solo"
        case .partEffects(let p):   return "\(p.title) FX On/Off"
        }
    }
}

/// The message a link listens for: kind, number and channel.
nonisolated struct MIDIControlSource: Codable, Hashable {
    var kind: MIDIControlMessage.Kind
    /// 1...16.
    var channel: Int
    var number: Int

    init(kind: MIDIControlMessage.Kind, channel: Int, number: Int) {
        self.kind = kind; self.channel = channel; self.number = number
    }

    init(_ message: MIDIControlMessage) {
        self.init(kind: message.kind, channel: message.channel, number: message.number)
    }

    func matches(_ message: MIDIControlMessage) -> Bool {
        kind == message.kind && channel == message.channel && number == message.number
    }

    /// "CC 7 · Ch 1", "Note C3 · Ch 10".
    var displayName: String {
        switch kind {
        case .controlChange: return "CC \(number) · Ch \(channel)"
        case .note:
            let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
            return "Note \(names[number % 12])\(number / 12 - 1) · Ch \(channel)"
        }
    }
}

/// One link: this message controls that target.
nonisolated struct MIDIControlMapping: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var source: MIDIControlSource
    var target: MIDIControlTarget
    /// For a continuous target: don't move the app's control until the hardware passes
    /// its current value, so a knob that is somewhere else does not make it jump.
    var pickup: Bool = false

    init(id: UUID = UUID(), source: MIDIControlSource, target: MIDIControlTarget,
         pickup: Bool = false) {
        self.id = id; self.source = source; self.target = target; self.pickup = pickup
    }

    // Tolerant decoder so templates saved before a field existed still load.
    private enum CodingKeys: String, CodingKey { case id, source, target, pickup }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try c.decode(MIDIControlSource.self, forKey: .source)
        target = try c.decode(MIDIControlTarget.self, forKey: .target)
        pickup = try c.decodeIfPresent(Bool.self, forKey: .pickup) ?? false
    }
}

/// A named set of links for one controller.
nonisolated struct MIDIControllerTemplate: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var mappings: [MIDIControlMapping] = []
    /// Shipped with the app. Built-ins are not edited in place: learning on one makes a
    /// copy, so the factory layout is always there to go back to.
    var isBuiltIn: Bool = false
    /// Part of a device name this template is for, so it can be chosen automatically
    /// the first time that controller is plugged in. Case-insensitive.
    var deviceNameHint: String? = nil

    init(id: UUID = UUID(), name: String, mappings: [MIDIControlMapping] = [],
         isBuiltIn: Bool = false, deviceNameHint: String? = nil) {
        self.id = id; self.name = name; self.mappings = mappings
        self.isBuiltIn = isBuiltIn; self.deviceNameHint = deviceNameHint
    }

    private enum CodingKeys: String, CodingKey { case id, name, mappings, isBuiltIn, deviceNameHint }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Controller"
        // A link to something a later version added (or this one dropped) is skipped,
        // not the whole template.
        mappings = (try? c.decodeIfPresent([LossyMapping].self, forKey: .mappings))?
            .compactMap(\.mapping) ?? []
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        deviceNameHint = try c.decodeIfPresent(String.self, forKey: .deviceNameHint)
    }

    private struct LossyMapping: Decodable {
        let mapping: MIDIControlMapping?
        init(from decoder: Decoder) throws { mapping = try? MIDIControlMapping(from: decoder) }
    }

    func mappings(matching message: MIDIControlMessage) -> [MIDIControlMapping] {
        mappings.filter { $0.source.matches(message) }
    }

    func mapping(for target: MIDIControlTarget) -> MIDIControlMapping? {
        mappings.first { $0.target == target }
    }

    /// Link `source` to `target`, replacing whatever either was linked to before: one
    /// control per message and one message per control keeps Learn predictable.
    mutating func learn(_ source: MIDIControlSource, for target: MIDIControlTarget) {
        mappings.removeAll { $0.source == source || $0.target == target }
        mappings.append(MIDIControlMapping(source: source, target: target))
    }

    mutating func forget(_ target: MIDIControlTarget) {
        mappings.removeAll { $0.target == target }
    }

    /// Whether this template is the one for a device of this name.
    func suits(deviceNamed deviceName: String) -> Bool {
        guard let hint = deviceNameHint, !hint.isEmpty else { return false }
        return deviceName.range(of: hint, options: .caseInsensitive) != nil
    }
}

// MARK: - Scaling

nonisolated enum MIDIControlScaling {
    /// Fader range in dB, the same as the on-screen faders. FaderScale is in the app
    /// target, outside this portable core, so its limits are repeated here: change both.
    static let volumeMinDB: Double = -60
    static let volumeMaxDB: Double = 6
    /// Tempo range a knob covers: auto-strum's whole range.
    static let tempoRange: ClosedRange<Double> = AutoStrum.tempoRange

    /// Linear gain for a 0...1 control position, laid out in dB like the faders.
    static func gain(forFraction f: Double) -> Float {
        let db = volumeMinDB + (volumeMaxDB - volumeMinDB) * min(max(f, 0), 1)
        return db <= volumeMinDB ? 0 : Float(pow(10, db / 20))
    }

    /// The 0...1 control position that corresponds to a linear gain (for pickup).
    static func fraction(forGain gain: Float) -> Double {
        guard gain > 0 else { return 0 }
        let db = max(volumeMinDB, 20 * log10(Double(gain)))
        return (db - volumeMinDB) / (volumeMaxDB - volumeMinDB)
    }

    static func pan(forFraction f: Double) -> Float { Float(min(max(f, 0), 1) * 2 - 1) }
    static func fraction(forPan p: Float) -> Double { (Double(p) + 1) / 2 }

    static func tempo(forFraction f: Double) -> Double {
        (tempoRange.lowerBound + (tempoRange.upperBound - tempoRange.lowerBound) * min(max(f, 0), 1)).rounded()
    }
    static func fraction(forTempo t: Double) -> Double {
        (t - tempoRange.lowerBound) / (tempoRange.upperBound - tempoRange.lowerBound)
    }
}

// MARK: - Pickup

/// Soft takeover for continuous links. With pickup on, an incoming position is ignored
/// until it reaches or crosses the app's current value — so turning a knob that sits
/// somewhere else does not make the control jump. Once caught, it follows directly
/// until the app's value is changed from elsewhere (touch, another controller).
nonisolated struct MIDIPickup {
    private var lastHardware: [UUID: Double] = [:]
    private var caught: Set<UUID> = []

    /// Whether to apply `incoming` (0...1) to a control currently at `current` (0...1).
    mutating func shouldApply(_ mapping: MIDIControlMapping, incoming: Double,
                              current: Double) -> Bool {
        defer { lastHardware[mapping.id] = incoming }
        guard mapping.pickup else { return true }
        // Close enough counts as caught: one step of a 7-bit knob is ~0.008.
        let tolerance = 1.5 / 127
        if caught.contains(mapping.id) {
            // Still in step with the app? Then keep following.
            if let last = lastHardware[mapping.id], abs(last - current) <= tolerance * 2 { return true }
            caught.remove(mapping.id)
        }
        if abs(incoming - current) <= tolerance {
            caught.insert(mapping.id); return true
        }
        if let last = lastHardware[mapping.id],
           (last - current) * (incoming - current) <= 0 {   // crossed the value
            caught.insert(mapping.id); return true
        }
        return false
    }

    mutating func reset() { lastHardware.removeAll(); caught.removeAll() }
}

// MARK: - Built-in templates

nonisolated enum MIDIBuiltInTemplates {
    /// Stable ids, so a built-in keeps its identity across launches and app updates.
    static let nanoKONTROL2ID = UUID(uuidString: "7A1C3E5B-2D4F-4A6B-8C9D-1E2F3A4B5C01")!

    /// Korg nanoKONTROL2, factory CC mode, global channel 1, laid out like FWD
    /// Sequencer's: the first four strips are the plate, auto-strum, drums and bass
    /// (fader, pan knob, S solo, M mute, R effects); fader 8 is the master and knob 8 the tempo.
    /// Transport: ▶ starts and stops the drums, ■ stops them, ● fills, cycle is HOLD,
    /// ◀◀ intro/outro, ▶▶ tap tempo, track ◀ ▶ variations A and B, marker ◀ ▶ styles.
    static let nanoKONTROL2: MIDIControllerTemplate = {
        var mappings: [MIDIControlMapping] = []
        func cc(_ number: Int, _ target: MIDIControlTarget, pickup: Bool = false) {
            mappings.append(MIDIControlMapping(
                id: UUID(uuidString: String(format: "7A1C3E5B-2D4F-4A6B-8C9D-%012lX", number))!,
                source: MIDIControlSource(kind: .controlChange, channel: 1, number: number),
                target: target, pickup: pickup))
        }
        for (strip, part) in HarpPart.allCases.enumerated() {
            cc(0 + strip, .partVolume(part))
            cc(16 + strip, .partPan(part))
            cc(32 + strip, .partSolo(part))
            cc(48 + strip, .partMute(part))
            cc(64 + strip, .partEffects(part))
        }
        cc(7, .masterVolume)
        cc(23, .tempo, pickup: true)
        cc(41, .rhythmStartStop)
        cc(42, .rhythmStop)
        cc(43, .introOutro)
        cc(44, .tapTempo)
        cc(45, .fill)
        cc(46, .hold)
        cc(58, .variationA)
        cc(59, .variationB)
        cc(61, .previousStyle)
        cc(62, .nextStyle)
        return MIDIControllerTemplate(id: nanoKONTROL2ID, name: "nanoKONTROL2 (factory)",
                                      mappings: mappings, isBuiltIn: true,
                                      deviceNameHint: "nanoKONTROL2")
    }()

    static let all: [MIDIControllerTemplate] = [nanoKONTROL2]
}

// MARK: - MIDI clock in

/// Works out the tempo of an incoming MIDI clock: 24 pulses a beat. The average of the
/// last beat's worth of pulse gaps, so one late pulse barely moves it; a gap of more than
/// half a second (the clock stopped) starts again.
nonisolated struct MIDIClockTempo {
    static let pulsesPerBeat = 24
    private var lastPulse: Double?
    private var gaps: [Double] = []

    /// A pulse at `time` (seconds). Returns the tempo once a beat's worth has arrived.
    mutating func pulse(at time: Double) -> Double? {
        defer { lastPulse = time }
        guard let last = lastPulse else { return nil }
        let gap = time - last
        guard gap > 0, gap < 0.5 else { gaps.removeAll(); return nil }
        gaps.append(gap)
        if gaps.count > Self.pulsesPerBeat { gaps.removeFirst(gaps.count - Self.pulsesPerBeat) }
        guard gaps.count == Self.pulsesPerBeat else { return nil }
        let average = gaps.reduce(0, +) / Double(gaps.count)
        let bpm = 60 / (average * Double(Self.pulsesPerBeat))
        return (bpm * 10).rounded() / 10
    }

    mutating func reset() { lastPulse = nil; gaps.removeAll() }
}
