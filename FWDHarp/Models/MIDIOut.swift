import Foundation

/// MIDI out (design brief): FWD Harp's notes sent to other iPad apps and to hardware,
/// each part on a channel of its own, so the plate and auto-strum can play different
/// instruments elsewhere, and the rhythm section's drums (channel 10) and bass can join
/// later. With FWD Harp's own sound switched off it is a pure controller.
nonisolated struct MIDIOutSettings: Codable, Equatable {
    /// Send MIDI at all. Off by default: nothing leaves the app until asked.
    var enabled = false
    /// Each part's own instrument in FWD Harp still plays (Graham, 2026-11-21: per
    /// part, so one can sound here while the other plays only in another app). Both
    /// off makes FWD Harp a controller only.
    var plateInternalSound = true
    var autoInternalSound = true
    /// Channels 1–16, as people number them.
    var plateChannel = 1
    var autoChannel = 2
    /// Destinations sent to directly (hardware, or an app's own MIDI input), by their
    /// CoreMIDI unique ID, which stays the same across launches. Other apps can also
    /// simply choose "FWD Harp" as their input, which needs nothing chosen here.
    var destinations: [Int32] = []

    static let channelRange = 1...16

    init() {}

    func playsOwnSound(_ part: HarpPart) -> Bool {
        part == .plate ? plateInternalSound : autoInternalSound
    }

    mutating func setPlaysOwnSound(_ on: Bool, for part: HarpPart) {
        if part == .plate { plateInternalSound = on } else { autoInternalSound = on }
    }

    func channel(for part: HarpPart) -> Int {
        part == .plate ? plateChannel : autoChannel
    }

    mutating func setChannel(_ channel: Int, for part: HarpPart) {
        let clamped = min(max(channel, Self.channelRange.lowerBound), Self.channelRange.upperBound)
        if part == .plate { plateChannel = clamped } else { autoChannel = clamped }
    }

    func normalized() -> MIDIOutSettings {
        var copy = self
        copy.setChannel(plateChannel, for: .plate)
        copy.setChannel(autoChannel, for: .auto)
        var seen = Set<Int32>()
        copy.destinations = destinations.filter { seen.insert($0).inserted }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, plateInternalSound, autoInternalSound, plateChannel, autoChannel, destinations
    }

    /// Read from files saved when one switch covered both parts.
    private enum LegacyKeys: String, CodingKey { case internalSound }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let both = try decoder.container(keyedBy: LegacyKeys.self)
            .decodeIfPresent(Bool.self, forKey: .internalSound) ?? true
        plateInternalSound = try c.decodeIfPresent(Bool.self, forKey: .plateInternalSound) ?? both
        autoInternalSound = try c.decodeIfPresent(Bool.self, forKey: .autoInternalSound) ?? both
        plateChannel = try c.decodeIfPresent(Int.self, forKey: .plateChannel) ?? 1
        autoChannel = try c.decodeIfPresent(Int.self, forKey: .autoChannel) ?? 2
        destinations = try c.decodeIfPresent([Int32].self, forKey: .destinations) ?? []
    }
}

/// The bytes of the MIDI 1.0 messages FWD Harp sends. `channel` is 1–16.
nonisolated enum MIDIBytes {
    static func status(_ kind: UInt8, channel: Int) -> UInt8 {
        kind | UInt8((min(max(channel, 1), 16) - 1) & 0x0F)
    }

    static func noteOn(_ note: UInt8, velocity: UInt8, channel: Int) -> [UInt8] {
        [status(0x90, channel: channel), note & 0x7F, max(1, velocity & 0x7F)]
    }

    static func noteOff(_ note: UInt8, channel: Int) -> [UInt8] {
        [status(0x80, channel: channel), note & 0x7F, 0]
    }

    static func controller(_ number: UInt8, value: UInt8, channel: Int) -> [UInt8] {
        [status(0xB0, channel: channel), number & 0x7F, value & 0x7F]
    }

    /// For a stuck note at the other end: sustain off and All Notes Off.
    static func panic(channel: Int) -> [UInt8] {
        controller(64, value: 0, channel: channel) + controller(123, value: 0, channel: channel)
    }
}
