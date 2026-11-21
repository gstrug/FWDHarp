import Foundation

/// The strum plate on the right (design brief, 2026-11-20): a tall strip of strings,
/// low at the bottom, each playing one note of the held chord, rising up the plate.
/// Touching further right plays louder.
///
/// The number of strings stays the same whatever the chord, so a strum lands in the
/// same place on every chord: with the 7th added, the same strings simply cover a
/// little less range. The plate pattern sets the order of the notes up the strings
/// (PlatePattern), so one sweep can play a broken-chord figure.
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
        notes(pitchClasses: Set(chord.pitchClasses), strings: strings, from: lowest)
    }

    /// The notes of a set of pitch classes in order up from `lowest`, one per string.
    static func notes(pitchClasses classes: Set<Int>, strings: Int, from lowest: Int) -> [Int] {
        guard !classes.isEmpty, strings > 0 else { return [] }
        var result: [Int] = []
        var note = lowest
        while result.count < strings, note <= 127 {
            if classes.contains(((note % 12) + 12) % 12) { result.append(note) }
            note += 1
        }
        return result
    }

    /// The note on each string in a plate pattern's order. Built from the straight run
    /// of the chord's notes from `lowest`; strings that would go past the top of MIDI
    /// are left off.
    static func notes(for chord: Chord, strings: Int, from lowest: Int, pattern: PlatePattern) -> [Int] {
        // Enough of the straight run for every pattern to look ahead into.
        let tones = notes(for: chord, strings: strings * 2 + 4, from: lowest)
        return ordered(tones, strings: strings, pattern: pattern, bass: bass(of: chord, below: tones))
    }

    /// A scale on the plate (PlateScale): its notes up from the scale's root, as many
    /// strings as the range's octaves hold, in the plate pattern's order. Bass + Chord
    /// has no chord to take a bass from here, so it plays Straight.
    static func notes(for scale: PlateScale, in key: MajorKey, octaves: Int, octaveShift: Int,
                      pattern: PlatePattern) -> [Int] {
        guard let classes = scale.pitchClasses(in: key) else { return [] }
        let strings = stringCount(octaves: octaves, scale: scale)
        let lowest = 48 + scale.root(in: key) + 12 * octaveShift
        let tones = notes(pitchClasses: classes, strings: strings * 2 + 4, from: lowest)
        return ordered(tones, strings: strings, pattern: pattern == .bassAndChord ? .straight : pattern,
                       bass: nil)
    }

    /// Strings on the plate: for a chord, 3 an octave plus the top root (the spread
    /// Graham likes); for a scale, every note of it across the same octaves, so a scale
    /// is never missing notes.
    static func stringCount(octaves: Int, scale: PlateScale) -> Int {
        guard let perOctave = scale.notesPerOctave else { return stringCount(octaves: octaves) }
        return max(1, octaves) * perOctave + 1
    }

    /// The straight run `tones` put in a plate pattern's order, one note per string.
    private static func ordered(_ tones: [Int], strings: Int, pattern: PlatePattern,
                                bass: (root: Int, fifth: Int)?) -> [Int] {
        guard strings > 0, !tones.isEmpty else { return [] }
        func tone(_ index: Int) -> Int? { tones.indices.contains(index) ? tones[index] : nil }
        var result: [Int?]
        switch pattern {
        case .straight:
            result = (0..<strings).map { tone($0) }
        case .alternating:
            // Each chord note, then the one two above it: 1 5 3 8 5 10 …
            result = (0..<strings).map { $0 % 2 == 0 ? tone($0 / 2) : tone($0 / 2 + 2) }
        case .rolling:
            // Two up, one back: 1 3 5 3 5 8 5 8 10 …
            result = (0..<strings).map { tone($0 / 3 + $0 % 3) }
        case .octaves:
            // Each chord note with its octave: 1 8 3 10 5 12 …
            result = (0..<strings).map { $0 % 2 == 0 ? tone($0 / 2) : tone($0 / 2).map { $0 + 12 } }
        case .bassAndChord:
            // The bottom strings rock between the root and 5th below the chord, the rest
            // run straight up above them.
            let bassStrings = max(2, Int(Double(strings) * 0.4))
            guard let bass else {
                result = (0..<strings).map { tone($0) }
                break
            }
            result = (0..<strings).map { index in
                if index < bassStrings { return index % 2 == 0 ? bass.root : bass.fifth }
                return tone(index - bassStrings)
            }
        }
        return result.compactMap { $0 }.filter { (0...127).contains($0) }
    }

    /// The chord's root an octave below its lowest root among `tones`, and the 5th
    /// above that (every chord the pads play has a 5th).
    static func bass(of chord: Chord, below tones: [Int]) -> (root: Int, fifth: Int)? {
        guard let lowestRoot = tones.first(where: { (($0 % 12) + 12) % 12 == chord.root }) else { return nil }
        let root = lowestRoot - 12 >= 0 ? lowestRoot - 12 : lowestRoot
        return (root, root + 7)
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

/// The order of the notes up the plate's strings, for strumming by hand. Straight is
/// the chord's notes low to high; the others make one sweep play a broken-chord figure
/// (design brief, "Plate patterns"). Sweeping down plays the figure in reverse.
nonisolated enum PlatePattern: String, CaseIterable, Codable {
    case straight, alternating, rolling, octaves, bassAndChord

    var title: String {
        switch self {
        case .straight: return "Straight"
        case .alternating: return "Alternating"
        case .rolling: return "Rolling"
        case .octaves: return "Octaves"
        case .bassAndChord: return "Bass + Chord"
        }
    }
}

/// What the plate plays: the held chord's notes (the default), or a scale in the key,
/// which limits the plate to that scale's notes so a melody or solo cannot hit a wrong
/// note (design brief, "Scales"). A scale plays whether or not a pad is held.
nonisolated enum PlateScale: String, CaseIterable, Codable {
    case chord, major, pentatonic, blues, naturalMinor, chromatic

    var title: String {
        switch self {
        case .chord: return "Chord"
        case .major: return "Major"
        case .pentatonic: return "Pentatonic"
        case .blues: return "Blues"
        case .naturalMinor: return "Natural Minor"
        case .chromatic: return "Chromatic"
        }
    }

    /// Semitones above the scale's root; nil for Chord.
    var intervals: [Int]? {
        switch self {
        case .chord: return nil
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .pentatonic: return [0, 2, 4, 7, 9]                // major pentatonic
        case .blues: return [0, 3, 5, 6, 7, 10]                 // C E♭ F F♯ G B♭ in C
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .chromatic: return Array(0..<12)
        }
    }

    var notesPerOctave: Int? { intervals?.count }

    /// The scale's own note: the key's note, except Natural Minor, which is the key's
    /// relative minor (A minor in C), so it shares the key's notes.
    func root(in key: MajorKey) -> Int {
        self == .naturalMinor ? (key.tonic + 9) % 12 : key.tonic
    }

    func pitchClasses(in key: MajorKey) -> Set<Int>? {
        guard let intervals else { return nil }
        let root = root(in: key)
        return Set(intervals.map { (root + $0) % 12 })
    }
}

/// How long a plucked plate note sounds before it is released (Graham, 2026-11-21: on
/// a synth, a note that rang until the next chord seemed to hang, since a synth keeps
/// sounding until it is released; a harp fades by itself). A note played again before
/// its time is struck afresh and timed from then.
nonisolated enum PlateRing: String, CaseIterable, Codable {
    case short, medium, long, untilChordChange

    var title: String {
        switch self {
        case .short: return "Short"
        case .medium: return "Medium"
        case .long: return "Long"
        case .untilChordChange: return "Until Chord"
        }
    }

    /// Seconds before the note is released; nil to ring until the chord changes.
    var seconds: Double? {
        switch self {
        case .short: return 0.4
        case .medium: return 1.2
        case .long: return 3
        case .untilChordChange: return nil
        }
    }
}
