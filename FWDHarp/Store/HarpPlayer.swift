import Foundation
import Combine

/// Playing the harp: the pads choose the chord, the plate plays its notes.
///
/// The pads make no sound of their own; all sound comes from the plate (design brief).
/// Plucked notes ring on, like a harp's strings, until:
/// - the same string is played again (it is struck afresh), or
/// - a different chord pad is pressed, which stops the old chord's notes at once, for
///   clean changes (the brief's rule with auto-strum off).
/// The modifiers (7th, sus2, sus4) stop nothing, so they can colour a ringing chord.
/// Lifting every pad leaves the notes ringing too; the plate is then silent until a pad
/// is pressed, unless Hold is on, which keeps the last chord chosen. This is the simplest version, to be adjusted once Graham has played it.
final class HarpPlayer: ObservableObject {
    let store: InstrumentStore

    @Published private(set) var selection = PadSelection()
    /// Strings with a finger on them, to light them.
    /// The strings lit under the fingers. On an object of their own: a strum changes
    /// them string by string, and only the plate's strings need to redraw for it, not
    /// every view that watches the harp (code review, 2026-11-23).
    let plateLights = PlateLights()

    /// Auto-strum on: pressing a pad sounds it, in the chosen pattern. Not saved; the
    /// app always opens with it off.
    @Published private(set) var isAutoStrumming = false

    /// The rhythm section: running, and where in the bar, for the beat light.
    /// What the rhythm section is doing: running, intro, fill, outro, INTRO lit.
    /// Changes only when one of those does; the beat itself is `beatClock`'s.
    @Published private(set) var rhythm = RhythmPosition()
    /// The bar and beat, for the beat lights alone: they change every beat, and
    /// nothing else on screen needs to redraw for that.
    let beatClock = BeatClock()
    /// SYNC: the rhythm waits and starts with the first pad (auto-strum on) or the
    /// first strum (auto-strum off), rather than at START. Not saved.
    @Published private(set) var isRhythmArmed = false

    /// Following an incoming MIDI clock (MIDI settings): it sets the tempo and the beat.
    @Published private(set) var isFollowingClock = false
    /// The incoming clock's tempo, once a beat of it has arrived.
    @Published private(set) var clockTempo: Double?

    /// Notes sounding from the plate, so they can be stopped or struck afresh.
    private var ringing: Set<UInt8> = []
    /// Bumped each time a note is plucked, so a release timed for an earlier pluck of
    /// the same note does not cut the new one short.
    private var plucks: [UInt8: Int] = [:]
    /// While Held: how many fingers hold each note. The same note can be on two
    /// strings (the plate orders repeat notes), so it is released when the last lets go.
    private var held: [UInt8: Int] = [:]
    /// One clock for auto-strum and the rhythm section, so they play together.
    private let strummer: Conductor
    private var tapper = TapTempo()
    private var cancellables = Set<AnyCancellable>()

    /// Makes its own InstrumentStore by default: the screen holds one HarpPlayer as a
    /// @StateObject, created exactly once, and the store with it.
    init(store: InstrumentStore = InstrumentStore()) {
        self.store = store
        strummer = Conductor(router: store.router)
        strummer.setPattern(store.setup.autoStrumPattern)
        strummer.setTempo(store.setup.tempo)
        strummer.setStyle(store.setup.rhythmStyle)
        strummer.setVariation(store.setup.rhythmVariation)
        strummer.onPosition = { [weak self] position in
            guard let self else { return }
            beatClock.show(position)
            var status = position
            status.bar = 0
            status.beat = 0
            guard status != rhythm else { return }
            let stopped = rhythm.running && !status.running
            rhythm = status
            // With HOLD on, the kept chord ends with the band, so auto-strum stops
            // with the drums (Graham, 2026-11-22), after STOP or an outro.
            if stopped, selection.isHolding { stopKeptChord() }
        }
        strummer.onClockTempo = { [weak self] bpm in self?.clockTempo = bpm }
        // Redraw when the key (in the store's setup) changes.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var key: MusicKey { store.setup.key }
    var chord: Chord? { selection.chord(in: key) }
    var plateScale: PlateScale { store.setup.plateScale }
    /// Strings on the plate: the number chosen, whatever it plays.
    var stringCount: Int { store.setup.plateStrings }
    var octaveShift: Int { store.setup.octaveShift }


    var platePattern: PlatePattern { store.setup.platePattern }
    var customPlateFigure: [Int] { store.setup.customPlateFigure }

    /// A new Custom figure: held strings follow it, as they follow a chord change.
    func setCustomPlateFigure(_ figure: [Int]) {
        store.setCustomPlateFigure(figure)
        retuneHeldStrings()
    }

    /// The note on each string, bottom string first, in the plate pattern's order: the
    /// scale chosen, or the chord held now (empty with none held).
    /// Kept until something it depends on changes: every string a strum crosses asks
    /// for it (code review, 2026-11-23).
    var plateNotes: [Int] {
        let inputs = PlateInputs(chord: chord, key: key, scale: plateScale, strings: stringCount,
                                 octaveShift: octaveShift, pattern: platePattern, custom: customPlateFigure)
        if let cached = plateNotesCache, cached.inputs == inputs { return cached.notes }
        let notes: [Int]
        if plateScale != .chord {
            notes = StrumPlate.notes(for: plateScale, in: key, chord: chord, strings: stringCount,
                                     octaveShift: octaveShift, pattern: platePattern)
        } else if let chord {
            notes = StrumPlate.notes(for: chord, strings: stringCount,
                                     from: StrumPlate.lowestNote(in: key, octaveShift: octaveShift),
                                     pattern: platePattern, custom: customPlateFigure)
        } else {
            notes = []
        }
        plateNotesCache = (inputs, notes)
        return notes
    }

    private struct PlateInputs: Equatable {
        let chord: Chord?
        let key: MusicKey
        let scale: PlateScale
        let strings: Int
        let octaveShift: Int
        let pattern: PlatePattern
        let custom: [Int]
    }
    private var plateNotesCache: (inputs: PlateInputs, notes: [Int])?

    /// The plate's notes in straight order, which auto-strum's figures are built from.
    private var straightNotes: [Int] {
        guard let chord else { return [] }
        return StrumPlate.notes(for: chord, strings: stringCount,
                                from: StrumPlate.lowestNote(in: key, octaveShift: octaveShift))
    }

    func setPlatePattern(_ pattern: PlatePattern) {
        store.setPlatePattern(pattern)
        retuneHeldStrings()
    }

    func setPlateScale(_ scale: PlateScale) {
        guard scale != plateScale else { return }
        stopRinging()
        store.setPlateScale(scale)
        syncAutoStrum(newPad: false)
    }

    /// The pad's chord in the current key, with the modifiers held now.
    func chord(on pad: ChordPad) -> Chord? {
        selection.chord(on: pad, in: key)
    }

    // MARK: Pads

    func press(_ pad: ChordPad) {
        let before = selection.current
        selection.press(pad)
        let changed = selection.current != before && selection.current != nil
        if changed { stopRinging() }
        syncAutoStrum(newPad: changed)
        // SYNC with auto-strum on: the first chord pad starts the band.
        if isRhythmArmed, isAutoStrumming, !pad.isModifier, chord != nil { startArmedRhythm() }
        // The same chord pad pressed again (Hold kept it sounding): auto-strum starts
        // its pattern again, so a single sweep can be swept again (Graham, 2026-11-21).
        if !pad.isModifier, !changed, selection.current == pad { strummer.retrigger() }
    }

    func release(_ pad: ChordPad) {
        let before = selection.current
        selection.release(pad)
        // Lifting one of two held pads hands over to the other: that is a change too.
        let changed = selection.current != before && selection.current != nil
        if changed { stopRinging() }
        syncAutoStrum(newPad: changed)
    }

    /// Hold: the last chord stays chosen after the left hand lifts. Not saved; the app
    /// always opens with it off.
    func setHolding(_ on: Bool) {
        selection.setHolding(on)
        syncAutoStrum(newPad: false)
    }

    /// STOP: let go of the chord Hold is keeping, so auto-strum's pattern ends and the
    /// plate goes quiet until the next pad. Hold stays on; notes ringing on the plate
    /// finish as they would.
    func stopKeptChord() {
        selection.releaseKept()
        syncAutoStrum(newPad: false)
    }

    func setPlateStrings(_ strings: Int) {
        store.setPlateStrings(strings)
        syncAutoStrum(newPad: false)
    }

    func shiftOctave(by step: Int) {
        store.setOctaveShift(octaveShift + step)
        syncAutoStrum(newPad: false)
    }

    func setKey(_ key: MusicKey) {
        guard key != self.key else { return }
        stopRinging()
        store.setKey(key)
        syncAutoStrum(newPad: false)
    }

    // MARK: Auto-strum

    var autoStrumPattern: AutoStrumPattern { store.setup.autoStrumPattern }
    var tempo: Double { store.setup.tempo }

    /// Give auto-strum its own instrument, or play it through the plate's.
    func setAutoHasOwnSound(_ own: Bool) {
        // Stopped first, so what is sounding is released on the instrument that
        // started it; then picked up again on the new one with the chord held.
        strummer.stop()
        store.setAutoHasOwnSound(own)
        syncAutoStrum(newPad: false)
    }

    func setAutoStrumming(_ on: Bool) {
        isAutoStrumming = on
        syncAutoStrum(newPad: false)
        strummer.setEnabled(on)
    }

    func setAutoStrumPattern(_ pattern: AutoStrumPattern) {
        store.setAutoStrumPattern(pattern)
        strummer.setPattern(pattern)
    }

    func setTempo(_ tempo: Double) {
        store.setTempo(tempo)
        strummer.setTempo(store.setup.tempo)
    }

    /// The clock, for MIDI in to drive: its pulses arrive on CoreMIDI's thread.
    var conductor: Conductor { strummer }

    /// Follow an incoming MIDI clock, or go back to the BPM set here.
    func setFollowsClock(_ on: Bool, transport: Bool) {
        strummer.setFollowsClock(on, transport: transport)
        if !on, isFollowingClock { strummer.setTempo(tempo) }
        isFollowingClock = on
        if !on { clockTempo = nil }
    }

    func tapTempo() {
        if let bpm = tapper.tap(at: ProcessInfo.processInfo.systemUptime) { setTempo(bpm) }
    }

    // MARK: Rhythm section

    var rhythmStyle: RhythmStyle { store.setup.rhythmStyle }
    var rhythmVariation: RhythmVariation { store.setup.rhythmVariation }
    /// INTRO lit: the next start plays the style's intro. It goes off once played.
    var rhythmIntro: Bool { rhythm.introArmed }

    /// The previous or next style in the menu's order, round the ends.
    func stepRhythmStyle(by step: Int) {
        let all = RhythmStyle.allCases
        guard let index = all.firstIndex(of: rhythmStyle) else { return }
        setRhythmStyle(all[(index + step + all.count) % all.count])
    }

    func setRhythmStyle(_ style: RhythmStyle) {
        store.setRhythmStyle(style)
        strummer.setStyle(style)
    }

    func setRhythmVariation(_ variation: RhythmVariation) {
        store.setRhythmVariation(variation)
        strummer.setVariation(variation)
    }

    func setRhythmIntro(_ on: Bool) {
        strummer.setIntro(on)
    }

    /// OUTRO: the style's ending from the next bar line, then the band stops.
    func outro() {
        strummer.outro()
    }

    /// START / STOP: the rhythm section at once (an armed SYNC is dropped).
    func toggleRhythm() {
        isRhythmArmed = false
        if strummer.isRhythmRunning { strummer.stopRhythm() } else { strummer.startRhythm() }
    }

    /// SYNC: wait for the first pad or strum. Lit while waiting.
    func armRhythm(_ on: Bool) {
        guard !strummer.isRhythmRunning else { isRhythmArmed = false; return }
        isRhythmArmed = on
    }

    private func startArmedRhythm() {
        isRhythmArmed = false
        strummer.startRhythm()
    }

    func fill() {
        strummer.fill()
    }

    /// Tell the strummer the chord and plate as they are now, and retune the strings
    /// fingers are holding to it.
    private func syncAutoStrum(newPad: Bool) {
        retuneHeldStrings()
        strummer.update(chord: chord, plateNotes: straightNotes,
                        scale: plateScale.autoStrumColour(in: key, chord: chord), newPad: newPad)
    }

    // MARK: Plate

    /// Each finger on the plate: its string, the note it is sounding there, how far
    /// across it is, and where it was when it touched (for the slide's expression).
    private struct PlateTouch {
        var string: Int
        var note: UInt8?
        var loudness: Double
        var anchor: Double
    }
    private var plateTouches: [ObjectIdentifier: PlateTouch] = [:]

    /// A finger touches the plate: its string sounds, `loudness` 0 (left) to 1 (right).
    func touchBegan(_ id: ObjectIdentifier, string: Int, loudness: Double) {
        let note = pluck(string: string, loudness: loudness)
        plateTouches[id] = PlateTouch(string: string, note: note, loudness: loudness, anchor: loudness)
        resetSlideWork?.cancel()
        applySlide(loudness: loudness, anchor: loudness)
        showTouchedStrings()
    }

    /// A finger moves: onto other strings (each one crossed sounds, in order), and
    /// across, which swells or softens the plate as it goes (Graham, 2026-11-23:
    /// sliding side to side for a vibrato-like wobble or a gentle swell).
    func touchMoved(_ id: ObjectIdentifier, string: Int, loudness: Double) {
        guard var touch = plateTouches[id] else { return }
        if string != touch.string {
            // Each string crossed sounds before the one before it is let go, so a note
            // on both is never cut. A string with the note this finger is already
            // sounding is not struck again: in a Custom figure neighbouring strings can
            // share a note (8 then the next round's 1), and cutting and restriking it a
            // few milliseconds apart clicked (Graham, 2026-11-25). It rings on.
            let notes = plateNotes
            var current = touch.note
            for crossed in StrumPlate.strings(crossedFrom: touch.string, to: string) {
                let wanted = notes.indices.contains(crossed) ? UInt8(notes[crossed]) : nil
                if let wanted, wanted == current, ringing.contains(wanted) { continue }
                let note = pluck(string: crossed, loudness: loudness)
                if let old = current { lift(note: old) }
                current = note
            }
            touch.string = string
            touch.note = current
            // A new string is a new pluck: the slide starts again from here.
            touch.anchor = loudness
        }
        touch.loudness = loudness
        plateTouches[id] = touch
        applySlide(loudness: loudness, anchor: touch.anchor)
        showTouchedStrings()
    }

    func touchEnded(_ id: ObjectIdentifier) {
        guard let touch = plateTouches.removeValue(forKey: id) else { return }
        if let note = touch.note { lift(note: note) }
        showTouchedStrings()
        // With every finger off, the slide goes back to where a finger lands once the
        // last notes have faded, so the next strum starts from the usual sound.
        if plateTouches.isEmpty {
            let work = DispatchWorkItem { [weak self] in
                guard let self, plateTouches.isEmpty else { return }
                send(store.setup.plateSlide.resting(depth: store.setup.slideDepth))
            }
            resetSlideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    private func showTouchedStrings() {
        plateLights.show(Set(plateTouches.values.map(\.string)))
    }

    /// A chord change (or a modifier, key, scale or octave change) while fingers hold
    /// strings: each held string changes to its note in the new chord, struck at the
    /// finger's loudness, so there is no need to lift and touch again (Graham,
    /// 2026-11-23). A string whose note is the same keeps sounding.
    private func retuneHeldStrings() {
        guard !plateTouches.isEmpty else { return }
        let notes = plateNotes
        for (id, touch) in plateTouches {
            let wanted = notes.indices.contains(touch.string) ? UInt8(notes[touch.string]) : nil
            // The same note, still sounding: left alone. (A pad change has just let
            // every note go, so there the same note is struck again.)
            if wanted == touch.note, touch.note.map(ringing.contains) ?? true { continue }
            if let old = touch.note { lift(note: old) }
            plateTouches[id]?.note = pluck(string: touch.string, loudness: touch.loudness)
        }
    }

    // MARK: Slide

    var plateSlide: PlateSlide { store.setup.plateSlide }
    var slideDepth: SlideDepth { store.setup.slideDepth }

    /// Choose what the slide controls. The control it leaves is set back to normal, so
    /// nothing is left bent or quietened.
    func setPlateSlide(_ slide: PlateSlide) {
        guard slide != plateSlide else { return }
        send(plateSlide.reset)
        store.setPlateSlide(slide)
        send(slide.resting(depth: slideDepth))
    }

    func setSlideDepth(_ depth: SlideDepth) {
        store.setSlideDepth(depth)
    }

    private var sentSlide: (status: UInt8, data1: UInt8, data2: UInt8)?
    private var resetSlideWork: DispatchWorkItem?

    /// The slide for a finger at `loudness` that landed at `anchor` (both 0–1 across).
    private func applySlide(loudness: Double, anchor: Double) {
        send(plateSlide.message(slide: loudness - anchor, depth: slideDepth))
    }

    private func send(_ message: (status: UInt8, data1: UInt8, data2: UInt8)?) {
        guard let message else { return }
        if let last = sentSlide, last == message { return }
        sentSlide = message
        store.router.performance(.plate, status: message.status, data1: message.data1, data2: message.data2)
    }

    /// Play one string, `loudness` 0 (left edge) to 1 (right edge). Returns the note
    /// played, which the finger hands back to `lift` when it leaves the string.
    @discardableResult
    func pluck(string: Int, loudness: Double) -> UInt8? {
        let notes = plateNotes
        guard notes.indices.contains(string) else { return nil }
        // SYNC with auto-strum off: the first strum starts the band.
        if isRhythmArmed, !isAutoStrumming { startArmedRhythm() }
        let note = UInt8(notes[string])
        // Always released first, even if the plate did not start it: auto-strum may
        // be sounding the same note on the same instrument, and a second note-on with
        // no note-off between can leave a note stuck in some instruments.
        store.noteOff(note)
        store.noteOn(note, velocity: StrumPlate.velocity(atWidth: loudness))
        ringing.insert(note)
        plucks[note, default: 0] += 1
        if plateRing == .whileHeld { held[note, default: 0] += 1 }
        if let seconds = plateRing.seconds {
            let pluck = plucks[note]
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, plucks[note] == pluck, ringing.contains(note) else { return }
                store.noteOff(note)
                ringing.remove(note)
            }
        }
        return note
    }

    /// A finger left the string where it started `note` (moved off it or lifted). With
    /// While Held, the note is released, unless another finger still holds it. Given
    /// the note itself, not the string: a 7th or sus added meanwhile changes what the
    /// string plays, and the note that is sounding is the one to release.
    func lift(note: UInt8) {
        guard plateRing == .whileHeld else { return }
        guard let count = held[note] else { return }
        if count > 1 { held[note] = count - 1; return }
        held.removeValue(forKey: note)
        if ringing.contains(note) {
            store.noteOff(note)
            ringing.remove(note)
        }
    }

    var plateRing: PlateRing { store.setup.plateRing }

    func setPlateRing(_ ring: PlateRing) {
        stopRinging()
        store.setPlateRing(ring)
    }

    /// MIDI panic, for a stuck note: stop auto-strum's notes and the plate's, and send
    /// every instrument All Sound Off, All Notes Off and a note-off for every note.
    /// AUTO and HOLD stay as they are; auto-strum starts again with the next pad.
    func panic() {
        strummer.stop()
        isRhythmArmed = false
        ringing.removeAll()
        held.removeAll()
        plateTouches.removeAll()
        plateLights.clear()
        // After the notes already handed to the router, so none sounds after PANIC.
        let engine = store.engine
        store.router.afterQueued { engine.panic() }
        // Every control the slide can move, back to normal.
        sentSlide = nil
        for slide in PlateSlide.allCases { send(slide.reset) }
        store.router.panicMIDI()
    }

    func stopRinging() {
        for note in ringing { store.noteOff(note) }
        ringing.removeAll()
        held.removeAll()
    }

    /// The harp is leaving the screen: lift every pad and silence the plate.
    func releaseAll() {
        selection.releaseAll()
        plateTouches.removeAll()
        plateLights.clear()
        stopRinging()
        strummer.stop()
        isRhythmArmed = false
        syncAutoStrum(newPad: false)
    }
}

/// The strings lit under the fingers (HarpPlayer.plateLights).
final class PlateLights: ObservableObject {
    @Published private(set) var touched: Set<Int> = []

    func show(_ strings: Set<Int>) {
        if strings != touched { touched = strings }
    }

    func clear() { show([]) }
}

/// The rhythm section's bar and beat, for the beat lights (HarpPlayer.beatClock).
final class BeatClock: ObservableObject {
    @Published private(set) var position = RhythmPosition()

    func show(_ new: RhythmPosition) {
        if new != position { position = new }
    }
}
