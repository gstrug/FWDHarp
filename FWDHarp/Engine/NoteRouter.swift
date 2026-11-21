import Foundation

/// Where a part's notes go: its instrument in the engine (unless FWD Harp's own sound
/// is switched off), and MIDI out on the part's channel (when it is on). The plate and
/// auto-strum both play through here, from the main thread and auto-strum's queue, so
/// it is thread-safe.
nonisolated final class NoteRouter: @unchecked Sendable {
    private let engine: AudioEngineManager
    private let midi: MIDIOutput
    private let lock = NSLock()

    // Guarded by `lock`.
    private var tracks: [HarpPart: UUID] = [:]
    private var settings = MIDIOutSettings()
    /// Notes sent out over MIDI and not yet released, per channel, so switching MIDI
    /// out off (or a channel change) can release them rather than leave them hanging
    /// in another app.
    private var sentNotes: [Int: Set<UInt8>] = [:]

    init(engine: AudioEngineManager, midi: MIDIOutput = .shared) {
        self.engine = engine
        self.midi = midi
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    /// The engine track a part's notes sound on.
    func setTrack(_ trackID: UUID, for part: HarpPart) {
        locked { tracks[part] = trackID }
    }

    func track(for part: HarpPart) -> UUID? {
        locked { tracks[part] }
    }

    func setSettings(_ new: MIDIOutSettings) {
        locked {
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

    func play(_ part: HarpPart, note: UInt8, velocity: UInt8) {
        locked {
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
        locked {
            // Always to the instrument, even with its sound switched off since the note
            // started: a note-off for a note not playing does no harm.
            if let track = tracks[part] { engine.stopNote(trackID: track, midiNote: note) }
            guard settings.enabled else { return }
            let channel = settings.channel(for: part)
            midi.send(MIDIBytes.noteOff(note, channel: channel))
            sentNotes[channel]?.remove(note)
        }
    }

    /// PANIC, at the other end of MIDI out too: each note sent is released, then
    /// sustain off and All Notes Off on each part's channel.
    func panicMIDI() {
        locked {
            guard settings.enabled else { sentNotes.removeAll(); return }
            releaseSentLocked(through: settings)
            for channel in Set(HarpPart.allCases.map(settings.channel(for:))) {
                midi.send(MIDIBytes.panic(channel: channel))
            }
        }
    }

    /// Caller holds `lock`. Sent through the destinations as they were (`old`) before
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
