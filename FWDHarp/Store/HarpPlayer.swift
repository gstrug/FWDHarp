import Foundation
import Combine

/// Playing the harp: the pads choose the chord, the plate plays its notes.
///
/// The pads make no sound of their own; all sound comes from the plate (design brief).
/// Plucked notes ring on, like a harp's strings, until:
/// - the same string is played again (it is struck afresh), or
/// - a different chord pad is pressed, which stops the old chord's notes at once, for
///   clean changes (the brief's rule with auto-strum off).
/// Adding or lifting the 7 stops nothing, so a 7th can be added to a ringing chord.
/// Lifting every pad leaves the notes ringing too; the plate is then silent until a pad
/// is pressed. This is the simplest version, to be adjusted once Graham has played it.
final class HarpPlayer: ObservableObject {
    let store: InstrumentStore

    @Published private(set) var selection = PadSelection()
    /// Strings with a finger on them, to light them.
    @Published private(set) var touchedStrings: Set<Int> = []

    /// Notes sounding from the plate, so they can be stopped or struck afresh.
    private var ringing: Set<UInt8> = []
    private var cancellables = Set<AnyCancellable>()

    /// Makes its own InstrumentStore by default: the screen holds one HarpPlayer as a
    /// @StateObject, created exactly once, and the store with it.
    init(store: InstrumentStore = InstrumentStore()) {
        self.store = store
        // Redraw when the key (in the store's setup) changes.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var key: MajorKey { store.setup.key }
    var chord: Chord? { selection.chord(in: key) }
    var stringCount: Int { StrumPlate.stringCount(octaves: StrumPlate.defaultOctaves) }

    /// The note on each string for the chord held now, bottom string first; empty with
    /// no chord held.
    var plateNotes: [Int] {
        guard let chord else { return [] }
        return StrumPlate.notes(for: chord, strings: stringCount, from: StrumPlate.lowestNote(in: key))
    }

    /// The pad's chord in the current key, with the 7th while the 7 is held.
    func chord(on pad: ChordPad) -> Chord? {
        guard let degree = pad.degree else { return nil }
        let chord = key.chord(degree: degree)
        return selection.seventhHeld ? chord.withSeventh : chord
    }

    // MARK: Pads

    func press(_ pad: ChordPad) {
        let before = selection.current
        selection.press(pad)
        if let now = selection.current, now != before { stopRinging() }
    }

    func release(_ pad: ChordPad) {
        let before = selection.current
        selection.release(pad)
        // Lifting one of two held pads hands over to the other: that is a change too.
        if let now = selection.current, now != before { stopRinging() }
    }

    func setKey(_ key: MajorKey) {
        guard key != self.key else { return }
        stopRinging()
        store.setKey(key)
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
    }
}
