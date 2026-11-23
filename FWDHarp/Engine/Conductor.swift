import Foundation

/// Where the rhythm section is, for the screen: running or not, the bar and beat,
/// and whether the intro or a fill is playing.
nonisolated struct RhythmPosition: Equatable {
    var running = false
    var bar = 0
    var beat = 0
    var intro = false
    var fill = false
    /// OUTRO pressed: waiting for the bar line, playing the last bar, or the final hit.
    var outro = false
    /// INTRO is lit: the next start plays the intro. It goes off once the intro has
    /// played (Graham, 2026-11-22).
    var introArmed = false
}

/// One clock for the rhythm section (drums and bass) and auto-strum, so they always
/// play together (Graham, 2026-11-21: "autostrum synced to rhythm"). It runs on its own
/// queue so the screen cannot hold it up, at 12 ticks a beat: sixteenths fall every 3
/// ticks, triplets every 4, eighths every 6 (or on the third triplet when the style
/// swings).
///
/// Each tick is due one tick after the previous tick was DUE (not when it ran), at the
/// tempo as it is then, so delays never add up into drift and a tempo change never
/// interrupts the beat (lesson learnt on 2026-11-21). Notes go through the NoteRouter
/// to each part's instrument and MIDI out, sent the moment they are due: never stamped
/// ahead (FWD lesson 5).
///
/// Auto-strum alone runs the clock from the first pad, as before. With the rhythm
/// running, auto-strum's steps fall on the rhythm's grid, counted from its first bar.
nonisolated final class Conductor: @unchecked Sendable {
    static let ticksPerBeat = 12

    private let router: NoteRouter
    private let queue = DispatchQueue(label: "com.fwdharp.conductor", qos: .userInteractive)
    private let lock = NSLock()
    /// Called on the main thread when the beat or the rhythm's state changes.
    var onPosition: ((RhythmPosition) -> Void)?

    // MARK: State, guarded by `lock`

    private var tempo: Double = AutoStrum.defaultTempo

    // Auto-strum.
    private var autoEnabled = false
    private var pattern: AutoStrumPattern = .arpeggioUp
    private var chord: Chord?
    private var plateNotes: [Int] = []
    private var scale: Set<Int>?
    private var autoSounding: [UInt8] = []
    /// The pattern's steps for the chord held, worked out when the chord, plate,
    /// scale or pattern change, so each step is a lookup.
    private var autoCycle: [[UInt8]] = []
    /// Bumped to cancel a single sweep in progress.
    private var sweepGeneration: UInt64 = 0

    // The rhythm section.
    private var style: RhythmStyle = .rock
    private var pendingStyle: RhythmStyle?
    private var variation: RhythmVariation = .a
    private var pendingVariation: RhythmVariation?
    private var introEnabled = false
    private var rhythmOn = false
    private var introActive = false
    /// The bar a fill plays in, and the step it starts from.
    private var fillBar: Int?
    private var fillFromStep = 0
    /// A crash on the next bar's first beat: after an intro or a fill.
    private var crashNext = false
    /// OUTRO: asked for (it starts at the next bar line), the bar it plays in, and,
    /// after the final hit, the tick the rhythm stops on.
    private var outroRequested = false
    private var outroBar: Int?
    private var endTick: Int?
    private var rhythmStartTick = 0
    /// The chord the bass plays: the one held, or the last one if none is.
    private var bassChord: Chord?
    private var bassSounding: (note: UInt8, endTick: Int)?
    private var drumsSounding: [(note: UInt8, releaseTick: Int)] = []

    // The clock.
    private var clockRunning = false
    private var clockGeneration: UInt64 = 0
    private var lastTick = -1
    private var autoOriginTick = 0

    // An incoming MIDI clock (Graham, 2026-11-22): it sets the tempo and the beat, and
    // its Start and Stop can start and stop the drums.
    private var followsClock = false
    private var clockTransport = true
    private var clockTempo = MIDIClockTempo()
    private var lastPulseTime: Double = -1
    /// Pulses since the clock's Start (or since following began).
    private var pulseIndex = 0
    /// After Start, its first pulse is due: the clock's own timing waits for it.
    private var awaitingPulseUntil: Double = -1
    private var reportedClockTempo: Double?
    /// The incoming clock's tempo, on the main thread, when it changes.
    var onClockTempo: ((Double?) -> Void)?

    init(router: NoteRouter) {
        self.router = router
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    // MARK: - Auto-strum

    /// The chord to play now (nil: none), from the plate's notes. `newPad` is true when
    /// a different chord pad was pressed, which is what triggers a single sweep.
    func update(chord: Chord?, plateNotes: [Int], scale: Set<Int>?, newPad: Bool) {
        locked {
            let hadChord = self.chord != nil
            self.chord = chord
            self.plateNotes = plateNotes
            self.scale = scale
            if let chord { bassChord = chord }
            rebuildAutoCycleLocked()
            if autoEnabled {
                if chord == nil {
                    releaseAutoLocked()
                } else if pattern == .singleSweep {
                    if newPad { sweepLocked() }
                } else if !hadChord, clockRunning, !rhythmOn {
                    // Auto-strum alone, picking up again: its pattern starts now (on
                    // the incoming clock's next eighth or beat, when following one).
                    autoOriginTick = alignedTickLocked(step: autoStepTicks)
                }
            }
            ensureClockLocked()
        }
    }

    /// The chord pad sounding was pressed again (with Hold, it never stopped): sweep
    /// again, or start the pattern again from its top. With the rhythm running the
    /// pattern stays on the rhythm's grid.
    func retrigger() {
        locked {
            guard autoEnabled, chord != nil else { return }
            if pattern == .singleSweep {
                sweepLocked()
            } else if !rhythmOn {
                releaseAutoLocked()
                autoOriginTick = alignedTickLocked(step: autoStepTicks)
            }
        }
    }

    func setEnabled(_ on: Bool) {
        locked {
            autoEnabled = on
            if !on {
                releaseAutoLocked()
            } else if chord != nil {
                if pattern == .singleSweep { sweepLocked() } else { autoOriginTick = alignedTickLocked(step: autoStepTicks) }
            }
            ensureClockLocked()
        }
    }

    func setPattern(_ newPattern: AutoStrumPattern) {
        locked {
            guard newPattern != pattern else { return }
            pattern = newPattern
            rebuildAutoCycleLocked()
            releaseAutoLocked()
            autoOriginTick = alignedTickLocked(step: autoStepTicks)
            ensureClockLocked()
        }
    }

    /// The tick already waiting keeps its time; every tick after it uses the new tempo.
    func setTempo(_ newTempo: Double) {
        locked { tempo = newTempo }
    }

    // MARK: - Following an incoming MIDI clock

    /// Follow a MIDI clock: its tempo and beat. `transport`: its Start and Stop start
    /// and stop the drums too.
    func setFollowsClock(_ on: Bool, transport: Bool) {
        locked {
            clockTransport = transport
            guard on != followsClock else { return }
            followsClock = on
            clockTempo.reset()
            lastPulseTime = -1
            pulseIndex = 0
            if !on { reportClockTempoLocked(nil) }
        }
    }

    /// 0xF8, on CoreMIDI's thread. Every second pulse is one of the music's ticks.
    func clockPulse(at time: Double) {
        locked {
            guard followsClock else { return }
            lastPulseTime = Self.now
            awaitingPulseUntil = -1
            if let bpm = clockTempo.pulse(at: time) {
                tempo = bpm
                reportClockTempoLocked(bpm)
            }
            let plays = pulseIndex % 2 == 0
            pulseIndex += 1
            if plays, clockRunning { advanceLocked() }
        }
    }

    /// 0xFA Start or 0xFB Continue: the next pulse is the first beat. With transport
    /// following on, the drums start with it.
    func clockStart() {
        locked {
            guard followsClock else { return }
            pulseIndex = 0
            awaitingPulseUntil = Self.now + 0.3
            if clockTransport, !rhythmOn { startRhythmLocked() }
        }
    }

    /// 0xFC Stop: with transport following on, the drums stop.
    func clockStop() {
        locked {
            guard followsClock, clockTransport, rhythmOn else { return }
            stopRhythmLocked()
            ensureClockLocked()
        }
    }

    private func reportClockTempoLocked(_ bpm: Double?) {
        if let bpm, let last = reportedClockTempo, abs(bpm - last) < 0.5 { return }
        guard bpm != nil || reportedClockTempo != nil else { return }
        reportedClockTempo = bpm
        DispatchQueue.main.async { [weak self] in self?.onClockTempo?(bpm) }
    }

    // MARK: - The rhythm section

    func setStyle(_ newStyle: RhythmStyle) {
        locked {
            if rhythmOn { pendingStyle = newStyle } else { style = newStyle }
        }
    }

    /// A or B: from the next bar while playing.
    func setVariation(_ newVariation: RhythmVariation) {
        locked {
            if rhythmOn { pendingVariation = newVariation } else { variation = newVariation }
        }
    }

    func setIntro(_ on: Bool) {
        locked {
            introEnabled = on
            reportAgain()
        }
    }

    /// OUTRO: the style's last bar from the next bar line, then a final hit, then the
    /// rhythm stops by itself.
    func outro() {
        locked {
            guard rhythmOn, !introActive, outroBar == nil, endTick == nil else { return }
            outroRequested = true
            fillBar = nil
            reportAgain()
        }
    }

    var isRhythmRunning: Bool { locked { rhythmOn } }

    /// START, or the first pad or strum with SYNC: on the next tick, with the intro
    /// first if it is on.
    func startRhythm() {
        locked { startRhythmLocked() }
    }

    private func startRhythmLocked() {
        do {
            guard !rhythmOn else { return }
            rhythmOn = true
            introActive = introEnabled
            fillBar = nil
            crashNext = false
            if let pendingStyle { style = pendingStyle; self.pendingStyle = nil }
            if let pendingVariation { variation = pendingVariation; self.pendingVariation = nil }
            // Following a clock: on its next beat.
            rhythmStartTick = clockRunning ? alignedTickLocked(step: Self.ticksPerBeat) : 0
            ensureClockLocked()
            report(bar: 0, beat: 0)
        }
    }

    /// STOP: at once, releasing the drums and bass. Auto-strum carries on if it is
    /// playing.
    func stopRhythm() {
        locked {
            guard rhythmOn else { return }
            stopRhythmLocked()
            ensureClockLocked()
        }
    }

    /// FILL: to the end of this bar, or through the next if this one is nearly over;
    /// then the style carries on, with a crash on the next bar.
    func fill() {
        locked {
            guard rhythmOn, !introActive, fillBar == nil, !isEndingLocked else { return }
            let ticksPerBar = Self.ticksPerBeat * style.beatsPerBar
            let elapsed = max(0, lastTick - rhythmStartTick)
            let bar = elapsed / ticksPerBar
            let tickInBar = elapsed % ticksPerBar
            let ticksPerStep = Self.ticksPerBeat / style.stepsPerBeat
            if tickInBar >= ticksPerBar * 3 / 4 {
                fillBar = bar + 1
                fillFromStep = 0
            } else {
                fillBar = bar
                fillFromStep = tickInBar / ticksPerStep + 1
            }
            report(bar: bar, beat: tickInBar / Self.ticksPerBeat)
        }
    }

    /// Stop everything and silence it: PANIC, leaving the screen, the app going away.
    func stop() {
        locked {
            if rhythmOn { stopRhythmLocked() }
            releaseAutoLocked()
            sweepGeneration &+= 1
            stopClockLocked()
        }
    }

    // MARK: - Caller holds `lock`

    private func stopRhythmLocked() {
        // Auto-strum carries on in the same place in its pattern.
        autoOriginTick = rhythmStartTick
        rhythmOn = false
        introActive = false
        fillBar = nil
        crashNext = false
        outroRequested = false
        outroBar = nil
        endTick = nil
        releaseBassLocked()
        for drum in drumsSounding { router.stop(.drums, note: drum.note) }
        drumsSounding = []
        reportStopped()
    }

    private var isEndingLocked: Bool { outroRequested || outroBar != nil || endTick != nil }

    private var needsClock: Bool {
        rhythmOn || (autoEnabled && chord != nil && pattern.isRhythmic)
    }

    private func ensureClockLocked() {
        if needsClock, !clockRunning {
            clockRunning = true
            clockGeneration &+= 1
            lastTick = -1
            // From the start, or, following a clock, from its next eighth or beat.
            autoOriginTick = alignedTickLocked(step: autoStepTicks)
            if rhythmOn { rhythmStartTick = alignedTickLocked(step: Self.ticksPerBeat) }
            schedule(at: .now())
        } else if !needsClock, clockRunning {
            stopClockLocked()
        }
    }

    private func stopClockLocked() {
        clockRunning = false
        clockGeneration &+= 1
        releaseAutoLocked()
    }

    private func releaseAutoLocked() {
        for note in autoSounding { router.stop(.auto, note: note) }
        autoSounding = []
    }

    private func releaseBassLocked() {
        if let bass = bassSounding { router.stop(.bass, note: bass.note) }
        bassSounding = nil
    }

    private func schedule(at due: DispatchTime) {
        let token = clockGeneration
        queue.asyncAfter(deadline: due) { [weak self] in
            self?.fire(due: due, token: token)
        }
    }

    /// The clock's own tick. While an incoming MIDI clock is driving, it only keeps
    /// time in reserve (it takes over if the clock stops arriving).
    private func fire(due: DispatchTime, token: UInt64) {
        locked {
            guard token == clockGeneration, clockRunning else { return }
            if !externalDrivingLocked { advanceLocked() }
            // From when this tick was due, at the tempo as it is now.
            let bpm = min(max(tempo, AutoStrum.tempoRange.lowerBound), AutoStrum.tempoRange.upperBound)
            let interval = 60 / bpm / Double(Self.ticksPerBeat)
            schedule(at: due + .nanoseconds(Int(interval * 1e9)))
        }
    }

    /// One tick of the music, from the clock's own timing or from an incoming MIDI clock.
    private func advanceLocked() {
        let tick = lastTick + 1
        lastTick = tick
        releaseDueLocked(tick)
        if rhythmOn { playRhythmLocked(tick) }
        playAutoLocked(tick)
    }

    // MARK: - Following an incoming MIDI clock (caller holds `lock`)

    /// Now, on the same clock as CoreMIDI's timestamps.
    private static var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

    /// An incoming clock is setting the beat: following is on, and a pulse has arrived
    /// lately (or Start has just come and its first pulse is on the way).
    private var externalDrivingLocked: Bool {
        guard followsClock else { return false }
        let now = Self.now
        return now - lastPulseTime < 0.3 || now < awaitingPulseUntil
    }

    /// The next tick to play on the incoming clock's grid: clock ticks are counted from
    /// its Start, two pulses (of 24 a beat) each.
    private var nextClockTick: Int { (pulseIndex + 1) / 2 }

    /// The first tick from now that falls on the incoming clock's grid of `step` ticks
    /// (12 a beat, 6 an eighth), so what starts now starts in time with the other app.
    /// Not following: the next tick.
    private func alignedTickLocked(step: Int) -> Int {
        guard externalDrivingLocked, step > 0 else { return lastTick + 1 }
        let wait = (step - nextClockTick % step) % step
        return lastTick + 1 + wait
    }

    /// Auto-strum's step on the grid: a beat for block chords, an eighth otherwise.
    private var autoStepTicks: Int { pattern.stepsPerBeat == 1 ? Self.ticksPerBeat : Self.ticksPerBeat / 2 }

    private func releaseDueLocked(_ tick: Int) {
        if let bass = bassSounding, bass.endTick <= tick { releaseBassLocked() }
        drumsSounding.removeAll { drum in
            guard drum.releaseTick <= tick else { return false }
            router.stop(.drums, note: drum.note)
            return true
        }
    }

    private func playRhythmLocked(_ tick: Int) {
        let elapsed = tick - rhythmStartTick
        guard elapsed >= 0 else { return }
        var ticksPerBar = Self.ticksPerBeat * style.beatsPerBar
        var tickInBar = elapsed % ticksPerBar
        var bar = elapsed / ticksPerBar

        if tickInBar == 0 {
            // A bar begins: the next style or variation, the end of an intro or fill.
            if let next = pendingStyle {
                style = next
                pendingStyle = nil
                // The bar is counted afresh in the new style's metre.
                rhythmStartTick = tick
                ticksPerBar = Self.ticksPerBeat * style.beatsPerBar
                tickInBar = 0
                bar = 0
            }
            if let next = pendingVariation { variation = next; pendingVariation = nil }
            if introActive, bar >= 1 {
                introActive = false
                introEnabled = false   // played: INTRO goes off, and the button turns to OUTRO
                crashNext = true
            }
            if let fill = fillBar, bar > fill { fillBar = nil; crashNext = true }
            if outroRequested { outroRequested = false; outroBar = bar; fillBar = nil }
            if let last = outroBar, bar > last {
                // The final hit: crash, kick and the bass's root, ringing two beats.
                outroBar = nil
                crashNext = false
                endTick = tick + 2 * Self.ticksPerBeat
                strikeLocked(DrumVoice.crash.note, velocity: 118, releaseTick: tick + Self.ticksPerBeat)
                strikeLocked(DrumVoice.kick.note, velocity: 118, releaseTick: tick + Self.ticksPerBeat)
                if let chord = bassChord {
                    releaseBassLocked()
                    let midi = UInt8(RhythmBass.root(of: chord))
                    router.play(.bass, note: midi, velocity: 110)
                    bassSounding = (midi, tick + 2 * Self.ticksPerBeat)
                }
                report(bar: bar, beat: 0)
                return
            }
        }
        if let end = endTick {
            if tick >= end {
                stopRhythmLocked()
                ensureClockLocked()
            }
            return
        }
        if tickInBar % Self.ticksPerBeat == 0 {
            report(bar: bar, beat: tickInBar / Self.ticksPerBeat)
        }

        let ticksPerStep = Self.ticksPerBeat / style.stepsPerBeat
        guard tickInBar % ticksPerStep == 0 else { return }
        let step = tickInBar / ticksPerStep
        // Looked up in the style's bars, read once (CompiledRhythmStyle).
        let compiled = style.compiled
        let main = compiled.bar(variation)
        let bars: CompiledRhythmBar
        if introActive {
            bars = compiled.intro
        } else if let last = outroBar, last == bar {
            bars = compiled.outro
        } else if let fill = fillBar, fill == bar, step >= fillFromStep {
            bars = compiled.fill
        } else {
            bars = main
        }
        guard bars.hits.indices.contains(step) else { return }

        if crashNext, step == 0 {
            strikeLocked(DrumVoice.crash.note, velocity: 110, releaseTick: tick + ticksPerStep)
            crashNext = false
        }
        for hit in bars.hits[step] {
            strikeLocked(hit.note, velocity: hit.velocity, releaseTick: tick + ticksPerStep)
        }

        // The bass follows the chord held, or the last one; it waits for a first chord.
        let bassLine = bars.hasBass ? bars : main
        if let event = bassLine.bass[step], let chord = bassChord,
           let note = RhythmBass.note(event.degree, over: chord), (0...127).contains(note) {
            releaseBassLocked()
            let midi = UInt8(note)
            router.play(.bass, note: midi, velocity: 100)
            bassSounding = (midi, tick + event.steps * ticksPerStep)
        }
    }

    private func rebuildAutoCycleLocked() {
        guard let chord, pattern.isRhythmic else { autoCycle = []; return }
        autoCycle = AutoStrum.cycle(pattern, plateNotes: plateNotes, chord: chord, scale: scale)
            .map { step in step.filter { (0...127).contains($0) }.map { UInt8($0) } }
    }

    /// One drum hit, released at `releaseTick`.
    private func strikeLocked(_ note: UInt8, velocity: UInt8, releaseTick: Int) {
        router.stop(.drums, note: note)
        router.play(.drums, note: note, velocity: velocity)
        drumsSounding.append((note, releaseTick))
    }

    private func playAutoLocked(_ tick: Int) {
        guard autoEnabled, chord != nil, pattern.isRhythmic else { return }
        let origin = rhythmOn ? rhythmStartTick : autoOriginTick
        let at = tick - origin
        guard at >= 0 else { return }
        let beatTick = at % Self.ticksPerBeat
        let beat = at / Self.ticksPerBeat
        let step: Int
        if pattern.stepsPerBeat == 1 {
            guard beatTick == 0 else { return }
            step = beat
        } else {
            // Eighths; the second swings onto the third triplet in a shuffle.
            let offbeat = rhythmOn && style.swings ? 8 : 6
            guard beatTick == 0 || beatTick == offbeat else { return }
            step = beat * 2 + (beatTick == 0 ? 0 : 1)
        }
        releaseAutoLocked()
        guard !autoCycle.isEmpty else { return }
        let notes = autoCycle[step % autoCycle.count]
        for note in notes {
            // Released first: the plate may be sounding it on the same instrument.
            router.stop(.auto, note: note)
            router.play(.auto, note: note, velocity: AutoStrum.velocity)
        }
        autoSounding = notes
    }

    /// One quick sweep up the whole plate. Its notes ring on until the next sweep or
    /// the chord is let go, like hand strumming.
    private func sweepLocked() {
        sweepGeneration &+= 1
        releaseAutoLocked()
        let token = sweepGeneration
        let notes = plateNotes.filter { (0...127).contains($0) }.map { UInt8($0) }
        for (index, note) in notes.enumerated() {
            queue.asyncAfter(deadline: .now() + Double(index) * AutoStrum.sweepGap) { [weak self] in
                guard let self else { return }
                locked {
                    guard token == self.sweepGeneration, self.autoEnabled else { return }
                    self.router.stop(.auto, note: note)
                    self.router.play(.auto, note: note, velocity: AutoStrum.velocity)
                    self.autoSounding.append(note)
                }
            }
        }
    }

    private var reportedBar = 0
    private var reportedBeat = 0

    /// The state has changed between beats: report it at the beat last shown.
    private func reportAgain() {
        if rhythmOn { report(bar: reportedBar, beat: reportedBeat) } else { reportStopped() }
    }

    private func report(bar: Int, beat: Int) {
        reportedBar = bar
        reportedBeat = beat
        let position = RhythmPosition(running: rhythmOn, bar: bar, beat: beat, intro: introActive,
                                      fill: fillBar != nil, outro: isEndingLocked, introArmed: introEnabled)
        DispatchQueue.main.async { [weak self] in self?.onPosition?(position) }
    }

    private func reportStopped() {
        let position = RhythmPosition(introArmed: introEnabled)
        DispatchQueue.main.async { [weak self] in self?.onPosition?(position) }
    }
}
