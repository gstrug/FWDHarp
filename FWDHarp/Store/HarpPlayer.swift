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

    /// Notes sounding from the plate, so they can be stopped or struck afresh.
    private var ringing: Set<UInt8> = []
    private let strummer: AutoStrummer
    private var tapper = TapTempo()
    private var cancellables = Set<AnyCancellable>()

    /// Makes its own InstrumentStore by default: the screen holds one HarpPlayer as a
    /// @StateObject, created exactly once, and the store with it.
    init(store: InstrumentStore = InstrumentStore()) {
        self.store = store
        strummer = AutoStrummer(engine: store.engine, partID: store.soundingTrackID(for: .auto))
        strummer.setPattern(store.setup.autoStrumPattern)
        strummer.setTempo(store.setup.tempo)
        // Redraw when the key (in the store's setup) changes.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var key: MajorKey { store.setup.key }
    var chord: Chord? { selection.chord(in: key) }
    var plateScale: PlateScale { store.setup.plateScale }
    /// Strings on the plate: fixed for chords, every note of a scale across the range.
    var stringCount: Int { StrumPlate.stringCount(octaves: store.setup.plateOctaves, scale: plateScale) }
    /// The chord's strings, which auto-strum builds on whatever the plate shows.
    private var chordStringCount: Int { StrumPlate.stringCount(octaves: store.setup.plateOctaves) }
    var octaveShift: Int { store.setup.octaveShift }
    var plateOctaves: Int { store.setup.plateOctaves }

    var platePattern: PlatePattern { store.setup.platePattern }

    /// The note on each string, bottom string first, in the plate pattern's order: the
    /// scale chosen, or the chord held now (empty with none held).
    var plateNotes: [Int] {
        if plateScale != .chord {
            return StrumPlate.notes(for: plateScale, in: key, octaves: plateOctaves,
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
        return StrumPlate.notes(for: chord, strings: chordStringCount,
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

    func setPlateOctaves(_ octaves: Int) {
        store.setPlateOctaves(octaves)
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
        store.setAutoHasOwnSound(own)
        strummer.setTarget(store.soundingTrackID(for: .auto))
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

    /// Tell the strummer the chord and plate as they are now.
    private func syncAutoStrum(newPad: Bool) {
        strummer.update(chord: chord, plateNotes: straightNotes, newPad: newPad)
    }

    // MARK: Plate

    /// Play one string, `loudness` 0 (left edge) to 1 (right edge).
    func pluck(string: Int, loudness: Double) {
        let notes = plateNotes
        guard notes.indices.contains(string) else { return }
        let note = UInt8(notes[string])
        if ringing.contains(note) { store.noteOff(note) }
        store.noteOn(note, velocity: StrumPlate.velocity(atWidth: loudness))
        ringing.insert(note)
    }

    func setTouchedStrings(_ strings: Set<Int>) {
        if strings != touchedStrings { touchedStrings = strings }
    }

    func stopRinging() {
        for note in ringing { store.noteOff(note) }
        ringing.removeAll()
    }

    /// The harp is leaving the screen: lift every pad and silence the plate.
    func releaseAll() {
        selection.releaseAll()
        touchedStrings = []
        stopRinging()
        strummer.stop()
        syncAutoStrum(newPad: false)
    }
}
