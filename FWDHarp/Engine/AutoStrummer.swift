import Foundation

/// Plays the auto-strum pattern in time, on its own queue so the screen cannot hold it
/// up. Notes go straight to the engine (thread-safe, and it holds MIDI back while a
/// plugin loads) and are sent the moment they are due: never stamped ahead (FWD
/// lesson 5).
///
/// Each step is due one interval after the moment the previous step was DUE (not when
/// it actually ran), so small delays never add up into drift. A tempo change takes
/// effect from the next step without interrupting the beat: dragging the tempo used to
/// restart the clock at every change, which held the pattern silent while the finger
/// moved (Graham, 2026-11-21). A chord change keeps the beat going; lifting every pad
/// (with Hold off) stops it.
nonisolated final class AutoStrummer: @unchecked Sendable {
    private let engine: AudioEngineManager
    private let partID: UUID
    private let queue = DispatchQueue(label: "com.fwdharp.autostrum", qos: .userInteractive)
    private let lock = NSLock()

    // Guarded by `lock`.
    private var enabled = false
    private var pattern: AutoStrumPattern = .arpeggioUp
    private var tempo: Double = AutoStrum.defaultTempo
    private var chord: Chord?
    private var plateNotes: [Int] = []
    /// Bumped to stop whatever is scheduled: a step from an older run does nothing.
    private var generation: UInt64 = 0
    private var running = false
    private var sounding: [UInt8] = []

    init(engine: AudioEngineManager, partID: UUID) {
        self.engine = engine
        self.partID = partID
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    /// The chord to play now (nil: none), from the plate's notes. `newPad` is true
    /// when a different chord pad was pressed, which is what triggers a single sweep.
    func update(chord: Chord?, plateNotes: [Int], newPad: Bool) {
        locked {
            self.chord = chord
            self.plateNotes = plateNotes
            guard enabled else { return }
            if chord == nil {
                stopLocked()
            } else if pattern == .singleSweep {
                if newPad { sweepLocked() }
            } else if !running {
                startLocked()
            }
        }
    }

    func setEnabled(_ on: Bool) {
        locked {
            enabled = on
            if !on { stopLocked(); return }
            if chord != nil {
                if pattern == .singleSweep { sweepLocked() } else { startLocked() }
            }
        }
    }

    func setPattern(_ newPattern: AutoStrumPattern) {
        locked {
            guard newPattern != pattern else { return }
            pattern = newPattern
            guard enabled else { return }
            stopLocked()
            if chord != nil, pattern.isRhythmic { startLocked() }
        }
    }

    /// The step already waiting keeps its time; every step after it uses the new tempo.
    func setTempo(_ newTempo: Double) {
        locked { tempo = newTempo }
    }

    /// Stop and silence (leaving the screen, the app going to the background).
    func stop() {
        locked { stopLocked() }
    }

    // MARK: Caller holds `lock`.

    private func startLocked() {
        generation &+= 1
        running = true
        schedule(step: 0, at: .now())
    }

    private func stopLocked() {
        generation &+= 1
        running = false
        releaseLocked()
    }

    private func releaseLocked() {
        for note in sounding { engine.stopNote(trackID: partID, midiNote: note) }
        sounding = []
    }

    private func schedule(step: Int, at due: DispatchTime) {
        let token = generation
        queue.asyncAfter(deadline: due) { [weak self] in
            self?.fire(step: step, due: due, token: token)
        }
    }

    private func fire(step: Int, due: DispatchTime, token: UInt64) {
        locked {
            guard token == generation, running, let chord else { return }
            releaseLocked()
            let notes = AutoStrum.notes(pattern, step: step, plateNotes: plateNotes, chord: chord)
                .filter { (0...127).contains($0) }
                .map { UInt8($0) }
            for note in notes {
                engine.playNote(trackID: partID, midiNote: note, velocity: AutoStrum.velocity)
            }
            sounding = notes
            // From when this step was due, at the tempo as it is now.
            let interval = AutoStrum.stepInterval(pattern, tempo: tempo)
            schedule(step: step + 1, at: due + .nanoseconds(Int(interval * 1e9)))
        }
    }

    /// One quick sweep up the whole plate. Its notes ring on until the next chord's
    /// sweep, like hand strumming.
    private func sweepLocked() {
        generation &+= 1
        running = false
        releaseLocked()
        let token = generation
        let notes = plateNotes.filter { (0...127).contains($0) }.map { UInt8($0) }
        for (index, note) in notes.enumerated() {
            queue.asyncAfter(deadline: .now() + Double(index) * AutoStrum.sweepGap) { [weak self] in
                guard let self else { return }
                locked {
                    guard token == self.generation else { return }
                    self.engine.playNote(trackID: self.partID, midiNote: note, velocity: AutoStrum.velocity)
                    self.sounding.append(note)
                }
            }
        }
    }
}
