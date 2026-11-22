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
    @Published private(set) var touchedStrings: Set<Int> = []

    /// Auto-strum on: pressing a pad sounds it, in the chosen pattern. Not saved; the
    /// app always opens with it off.
    @Published private(set) var isAutoStrumming = false

    /// The rhythm section: running, and where in the bar, for the beat light.
    @Published private(set) var rhythm = RhythmPosition()
    /// SYNC: the rhythm waits and starts with the first pad (auto-strum on) or the
    /// first strum (auto-strum off), rather than at START. Not saved.
    @Published private(set) var isRhythmArmed = false

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
            guard let self, position != rhythm else { return }
            let stopped = rhythm.running && !position.running
            rhythm = position
            // With HOLD on, the kept chord ends with the band, so auto-strum stops
            // with the drums (Graham, 2026-11-22), after STOP or an outro.
            if stopped, selection.isHolding { stopKeptChord() }
        }
        // Redraw when the key (in the store's setup) changes.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var key: MajorKey { store.setup.key }
    var chord: Chord? { selection.chord(in: key) }
    var plateScale: PlateScale { store.setup.plateScale }
    /// Strings on the plate: the number chosen, whatever it plays.
    var stringCount: Int { store.setup.plateStrings }
    var octaveShift: Int { store.setup.octaveShift }


    var platePattern: PlatePattern { store.setup.platePattern }

    /// The note on each string, bottom string first, in the plate pattern's order: the
    /// scale chosen, or the chord held now (empty with none held).
    var plateNotes: [Int] {
        if plateScale != .chord {
            return StrumPlate.notes(for: plateScale, in: key, chord: chord, strings: stringCount,
                                    octaveShift: octaveShift, pattern: platePattern)
        }
        guard let chord else { return [] }
        return StrumPlate.notes(for: chord, strings: stringCount,
                                from: StrumPlate.lowestNote(in: key, octaveShift: octaveShift),
                                pattern: platePattern)
    }

    /// The plate's notes in straight order, which auto-strum's figures are built from.
    private var straightNotes: [Int] {
        guard let chord else { return [] }
        return StrumPlate.notes(for: chord, strings: stringCount,
                                from: StrumPlate.lowestNote(in: key, octaveShift: octaveShift))
    }

    func setPlatePattern(_ pattern: PlatePattern) {
        store.setPlatePattern(pattern)
    }

    func setPlateScale(_ scale: PlateScale) {
        guard scale != plateScale else { return }
        stopRinging()
        touchedStrings = []
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
        touchedStrings = []
        syncAutoStrum(newPad: false)
    }

    func shiftOctave(by step: Int) {
        store.setOctaveShift(octaveShift + step)
        syncAutoStrum(newPad: false)
    }

    func setKey(_ key: MajorKey) {
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

    func tapTempo() {
        if let bpm = tapper.tap(at: ProcessInfo.processInfo.systemUptime) { setTempo(bpm) }
    }

    // MARK: Rhythm section

    var rhythmStyle: RhythmStyle { store.setup.rhythmStyle }
    var rhythmVariation: RhythmVariation { store.setup.rhythmVariation }
    /// INTRO lit: the next start plays the style's intro. It goes off once played.
    var rhythmIntro: Bool { rhythm.introArmed }

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

    /// Tell the strummer the chord and plate as they are now.
    private func syncAutoStrum(newPad: Bool) {
        strummer.update(chord: chord, plateNotes: straightNotes,
                        scale: plateScale.autoStrumColour(in: key, chord: chord), newPad: newPad)
    }

    // MARK: Plate

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

    func setTouchedStrings(_ strings: Set<Int>) {
        if strings != touchedStrings { touchedStrings = strings }
    }

    /// MIDI panic, for a stuck note: stop auto-strum's notes and the plate's, and send
    /// every instrument All Sound Off, All Notes Off and a note-off for every note.
    /// AUTO and HOLD stay as they are; auto-strum starts again with the next pad.
    func panic() {
        strummer.stop()
        isRhythmArmed = false
        ringing.removeAll()
        held.removeAll()
        touchedStrings = []
        store.engine.panic()
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
        touchedStrings = []
        stopRinging()
        strummer.stop()
        isRhythmArmed = false
        syncAutoStrum(newPad: false)
    }
}
