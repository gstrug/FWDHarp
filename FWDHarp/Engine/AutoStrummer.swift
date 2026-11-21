import Foundation

/// Plays the auto-strum pattern in time, on its own queue so the screen cannot hold it
/// up. Notes go straight to the engine (thread-safe, and it holds MIDI back while a
/// plugin loads) and are sent the moment they are due: never stamped ahead (FWD
/// lesson 5).
///
/// Each step is timed from the moment the pattern started, not from the step before,
/// so small delays never add up into drift. A chord change while it runs keeps the
/// beat going; lifting every pad (with Hold off) stops it.
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
    private var startTime: DispatchTime = .now()
    /// Beats already played before the tempo last changed, so a tempo change carries
    /// on from where the beat is rather than jumping.
    private var stepsBeforeTempoChange = 0
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

    func setTempo(_ newTempo: Double) {
        locked {
            guard newTempo != tempo else { return }
            if running {
                // Restart the clock from the next step, at the new speed.
                let interval = AutoStrum.stepInterval(pattern, tempo: tempo)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- startTime.uptimeNanoseconds) / 1e9
                stepsBeforeTempoChange += Int(elapsed / max(interval, 0.001)) + 1
                tempo = newTempo
                generation &+= 1
                // The next step one new interval from now: dragging the tempo sends
                // many changes, and firing at each one would rattle off notes.
                startTime = .now()
                scheduleLocked(step: stepsBeforeTempoChange, offset: 1)
            } else {
                tempo = newTempo
            }
        }
    }

    /// Stop and silence (leaving the screen, the app going to the background).
    func stop() {
        locked { stopLocked() }
    }

    // MARK: Caller holds `lock`.

    private func startLocked() {
        generation &+= 1
        running = true
        startTime = .now()
        stepsBeforeTempoChange = 0
        scheduleLocked(step: 0, offset: 0)
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

    /// `offset`: steps since `startTime`.
    private func scheduleLocked(step: Int, offset: Int) {
        let interval = AutoStrum.stepInterval(pattern, tempo: tempo)
        let due = startTime + .nanoseconds(Int(Double(offset) * interval * 1e9))
        let token = generation
        queue.asyncAfter(deadline: due) { [weak self] in
            self?.fire(step: step, offset: offset, token: token)
        }
    }

    private func fire(step: Int, offset: Int, token: UInt64) {
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
            scheduleLocked(step: step + 1, offset: offset + 1)
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
