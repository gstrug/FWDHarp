import Foundation

/// Where a part's notes go: its instrument in the engine (unless FWD Harp's own sound
/// is switched off), and MIDI out on the part's channel (when it is on). The plate,
/// auto-strum and the rhythm section all play through here.
///
/// Everything is SENT FROM ITS OWN QUEUE (code review after a hang, 2026-11-25): a
/// caller hands the note over and carries straight on. Before, the screen sent each
/// note itself and waited for the instrument to take it, and a built-in sound takes
/// notes only between its own audio work; with the iPad busy, a fast strum made the
/// screen wait note after note, and the beat clock, waiting the same way with its
/// lock held, could hold up a pad press too. One serial queue keeps every note in the
/// order it was played; handing over costs a few microseconds.
nonisolated final class NoteRouter: @unchecked Sendable {
    private let engine: AudioEngineManager
    private let midi: MIDIOutput
    private let queue = DispatchQueue(label: "com.fwdharp.notes", qos: .userInteractive)

    // Only touched on `queue`.
    private var tracks: [HarpPart: UUID] = [:]
    private var settings = MIDIOutSettings()
    /// Notes sent out over MIDI and not yet released, per channel, so switching MIDI
    /// out off (or a channel change) can release them rather than leave them hanging
    /// in another app.
    private var sentNotes: [Int: Set<UInt8>] = [:]
    /// Parts muted, or silenced by another part's solo: their new notes go nowhere,
    /// not to the instrument and not to MIDI out (Graham, 2026-11-27). Note-offs still
    /// go, so nothing already sounding is left hanging.
    private var silenced: Set<HarpPart> = []

    init(engine: AudioEngineManager, midi: MIDIOutput = .shared) {
        self.engine = engine
        self.midi = midi
    }

    /// Runs `body` on the queue, after everything handed over before it.
    private func locked(_ body: @escaping @Sendable () -> Void) {
        queue.async(execute: body)
    }

    /// Engine work that must come after the notes already handed over, such as an
    /// all-notes-off or PANIC: run in turn on the same queue.
    func afterQueued(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// The engine track a part's notes sound on.
    func setTrack(_ trackID: UUID, for part: HarpPart) {
        locked { self.tracks[part] = trackID }
    }

    func setSettings(_ new: MIDIOutSettings) {
        locked { [self] in
            let old = settings
            settings = new
            midi.setDestinations(new.enabled ? new.destinations : [])
            // Release what the other end is holding if MIDI out went off or a part
            // moved channel: those note-offs would otherwise never be sent.
            if old.enabled, !new.enabled || old.channels != new.channels || old.destinations != new.destinations {
                releaseSentLocked(through: old)
            }
        }
    }

    /// Which parts are silent now. A part that has just gone silent has its notes at
    /// the other end of MIDI out released, so another app stops it too.
    func setSilenced(_ parts: Set<HarpPart>) {
        locked { [self] in
            let newly = parts.subtracting(silenced)
            silenced = parts
            guard settings.enabled, !newly.isEmpty else { return }
            // A channel still used by a part that is playing is left alone.
            let playing = Set(HarpPart.allCases.filter { !parts.contains($0) }.map(settings.channel(for:)))
            for channel in Set(newly.map(settings.channel(for:))) where !playing.contains(channel) {
                for note in sentNotes[channel] ?? [] { midi.send(MIDIBytes.noteOff(note, channel: channel)) }
                sentNotes[channel] = nil
            }
        }
    }

    func play(_ part: HarpPart, note: UInt8, velocity: UInt8) {
        locked { [self] in
            guard !silenced.contains(part) else { return }
            if settings.playsOwnSound(part), let track = tracks[part] {
                engine.playNote(trackID: track, midiNote: note, velocity: velocity)
            }
            guard settings.enabled else { return }
            let channel = settings.channel(for: part)
            midi.send(MIDIBytes.noteOn(note, velocity: velocity, channel: channel))
            sentNotes[channel, default: []].insert(note)
        }
    }

    func stop(_ part: HarpPart, note: UInt8) {
        locked { [self] in
            // Always to the instrument, even with its sound switched off since the note
            // started: a note-off for a note not playing does no harm.
            if let track = tracks[part] { engine.stopNote(trackID: track, midiNote: note) }
            guard settings.enabled else { return }
            let channel = settings.channel(for: part)
            midi.send(MIDIBytes.noteOff(note, channel: channel))
            sentNotes[channel]?.remove(note)
        }
    }

    /// A controller, pitch bend or channel aftertouch (`status` 0xB0, 0xE0 or 0xD0, for
    /// the plate's slide) to the part's instrument and its MIDI channel.
    func performance(_ part: HarpPart, status: UInt8, data1: UInt8, data2: UInt8) {
        locked { [self] in
            if settings.playsOwnSound(part), let track = tracks[part] {
                engine.sendPerformanceMessage(trackID: track, status: status, data1: data1, data2: data2)
            }
            guard settings.enabled else { return }
            let first = MIDIBytes.status(status & 0xF0, channel: settings.channel(for: part))
            midi.send(status & 0xF0 == 0xD0 ? [first, data1 & 0x7F] : [first, data1 & 0x7F, data2 & 0x7F])
        }
    }

    /// PANIC, at the other end of MIDI out too: each note sent is released, then
    /// sustain off and All Notes Off on each part's channel.
    func panicMIDI() {
        locked { [self] in
            guard settings.enabled else { sentNotes.removeAll(); return }
            releaseSentLocked(through: settings)
            for channel in Set(HarpPart.allCases.map(settings.channel(for:))) {
                midi.send(MIDIBytes.panic(channel: channel))
            }
        }
    }

    /// On `queue`. Sent through the destinations as they were (`old`) before
    /// a change, so the release goes where its note-on went.
    private func releaseSentLocked(through old: MIDIOutSettings) {
        guard !sentNotes.isEmpty else { return }
        midi.setDestinations(old.destinations)
        for (channel, notes) in sentNotes {
            for note in notes { midi.send(MIDIBytes.noteOff(note, channel: channel)) }
        }
        sentNotes.removeAll()
        midi.setDestinations(settings.enabled ? settings.destinations : [])
    }
}
