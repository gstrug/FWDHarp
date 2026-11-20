import Foundation

// Copied from FWD Sequencer (MIDIControl.swift) on 2026-11-20: decoding only. MIDI Learn
// (links from controller knobs and buttons to the app's controls) comes with the pads.

/// One incoming MIDI 1.0 control change or note.
nonisolated struct MIDIControlMessage: Equatable {
    enum Kind: String, Codable, Equatable {
        /// Control change: number = controller, value = 0...127.
        case controlChange
        /// Note on/off: number = note, value = velocity (0 for a note off).
        case note
    }
    var kind: Kind
    /// 1...16, as shown to people.
    var channel: Int
    var number: Int
    var value: Int

    /// Decode three MIDI 1.0 bytes. Anything that is not a CC, note on or note off is
    /// not something a link can be made to, and returns nil.
    init?(status: UInt8, data1: UInt8, data2: UInt8) {
        let type = status & 0xF0
        channel = Int(status & 0x0F) + 1
        number = Int(data1 & 0x7F)
        switch type {
        case 0xB0: kind = .controlChange; value = Int(data2 & 0x7F)
        case 0x90: kind = .note; value = Int(data2 & 0x7F)   // velocity 0 is a note off
        case 0x80: kind = .note; value = 0
        default: return nil
        }
    }

    init(kind: Kind, channel: Int, number: Int, value: Int) {
        self.kind = kind; self.channel = channel; self.number = number; self.value = value
    }

    /// A button counts as pressed above half way. Notes are pressed while sounding.
    var isPress: Bool { value >= 64 || (kind == .note && value > 0) }

    /// The value as 0...1.
    var fraction: Double { Double(value) / 127 }
}
