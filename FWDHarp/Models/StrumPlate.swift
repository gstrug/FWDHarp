import Foundation

/// The strum plate on the right (design brief, 2026-11-20): a tall strip of strings,
/// low at the bottom, each playing one note of the held chord, rising up the plate.
/// Touching further right plays louder.
///
/// The number of strings stays the same whatever the chord, so a strum lands in the
/// same place on every chord: with the 7th added, the same strings simply cover a
/// little less range. This first version has one pattern, Straight (the chord's notes
/// in order, low to high); the other plate patterns wait for Graham's first playing
/// test.
nonisolated enum StrumPlate {
    /// The brief's starting range, 3 octaves of a three-note chord root to root (10
    /// strings), is also the narrowest: Graham likes that spread. Wider ranges put more
    /// strings in the same height.
    static let minimumOctaves = 3
    static let maximumOctaves = 5
    static let octaveRange = minimumOctaves...maximumOctaves
    /// How far the octave buttons move the plate, in octaves.
    static let octaveShiftRange = -2...2
    /// Softest and loudest, left edge to right edge.
    static let softestVelocity = 30
    static let loudestVelocity = 127

    static func stringCount(octaves: Int) -> Int {
        max(1, octaves) * 3 + 1
    }

    /// The bottom string starts at the key's own note in the octave below middle C
    /// (C3 to B3), so the plate sits in the same place in every key; the octave buttons
    /// move it by whole octaves.
    static func lowestNote(in key: MajorKey, octaveShift: Int = 0) -> Int {
        48 + key.tonic + 12 * octaveShift
    }

    /// The note on each string, bottom string first: the chord's notes in order,
    /// starting from the first one at or above `lowest`.
    static func notes(for chord: Chord, strings: Int, from lowest: Int) -> [Int] {
        let classes = Set(chord.pitchClasses)
        guard !classes.isEmpty, strings > 0 else { return [] }
        var result: [Int] = []
        var note = lowest
        while result.count < strings, note <= 127 {
            if classes.contains(((note % 12) + 12) % 12) { result.append(note) }
            note += 1
        }
        return result
    }

    /// Which string is at a height, 0 at the bottom edge and 1 at the top.
    static func string(atHeight fraction: Double, strings: Int) -> Int {
        guard strings > 0 else { return 0 }
        let clamped = min(max(fraction, 0), 0.999_999)
        return Int(clamped * Double(strings))
    }

    /// How loud, from 0 at the left edge to 1 at the right.
    static func velocity(atWidth fraction: Double) -> UInt8 {
        let clamped = min(max(fraction, 0), 1)
        let value = Double(softestVelocity) + clamped * Double(loudestVelocity - softestVelocity)
        return UInt8(value.rounded())
    }

    /// The strings a finger crossed moving from one string to another, in the order it
    /// crossed them: every string after `from`, up to and including `to`. A fast strum
    /// can skip strings between two touch reports; this plays them all.
    static func strings(crossedFrom from: Int, to: Int) -> [Int] {
        if to > from { return Array((from + 1)...to) }
        if to < from { return Array((to...(from - 1)).reversed()) }
        return []
    }
}
