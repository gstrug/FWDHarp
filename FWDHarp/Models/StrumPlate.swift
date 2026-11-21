import Foundation

/// The strum plate on the right (design brief, 2026-11-20): a tall strip of strings,
/// low at the bottom, each playing one note of the held chord, rising up the plate.
/// Touching further right plays louder.
///
/// The number of strings is chosen (STRINGS) and stays the same whatever the chord or
/// scale, like a real harp's, so a strum lands in the same place every time and the
/// strings never crowd (Graham, 2026-11-21: Chromatic over 3 octaves made 37 strings).
/// More notes per octave simply means the same strings cover less range. The plate
/// pattern sets the order of the notes up the strings (PlatePattern), so one sweep can
/// play a broken-chord figure.
nonisolated enum StrumPlate {
    /// 10 is the spread Graham likes (3 octaves of a three-note chord, root to root),
    /// and the fewest.
    static let stringChoices = [10, 13, 16, 20, 24]
    static let defaultStrings = 10
    /// How far the octave buttons move the plate, in octaves.
    static let octaveShiftRange = -2...2
    /// Softest and loudest, left edge to right edge.
    static let softestVelocity = 30
    static let loudestVelocity = 127

    /// The string count a setup saved with the old RANGE (3, 4 or 5 octaves of a
    /// chord) had.
    static func strings(forOldOctaves octaves: Int) -> Int {
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

    /// A scale on the plate (PlateScale), one note per string up from the plate's
    /// bottom (the key's note, moved by OCT), in the plate pattern's order. Pentatonic
    /// and Blues follow `chord`, the one held now. Bass + Chord has no chord to take a
    /// bass from, so it plays Straight.
    static func notes(for scale: PlateScale, in key: MajorKey, chord: Chord?, strings: Int,
                      octaveShift: Int, pattern: PlatePattern) -> [Int] {
        guard let classes = scale.pitchClasses(in: key, chord: chord) else { return [] }
        let tones = notes(pitchClasses: classes, strings: strings * 2 + 4,
                          from: lowestNote(in: key, octaveShift: octaveShift))
        return ordered(tones, strings: strings, pattern: pattern == .bassAndChord ? .straight : pattern,
                       bass: nil)
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

/// What the plate plays: the held chord's notes (the default), or a scale, which
/// limits the plate to that scale's notes so a melody or solo cannot hit a wrong note
/// (design brief, "Scales"). A scale plays whether or not a pad is held.
///
/// Major, Natural Minor and Chromatic are the key's. Pentatonic and Blues FOLLOW THE
/// CHORD held (Graham, 2026-11-21: Blues on the key's note clashed with the other
/// chords): built on its root, major over a major chord (C D E G A; blues C D E♭ E G
/// A), minor over a minor or sus4 chord (A C D E G; blues A C D E♭ E G). With no chord
/// held, on the key's note, major.
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

    var followsChord: Bool { self == .pentatonic || self == .blues }

    /// Semitones above the scale's root; nil for Chord. `minor` picks the minor form of
    /// the scales that follow the chord.
    func intervals(minor: Bool = false) -> [Int]? {
        switch self {
        case .chord: return nil
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .pentatonic: return minor ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9]
        case .blues: return minor ? [0, 3, 5, 6, 7, 10] : [0, 2, 3, 4, 7, 9]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]   // the key's relative minor
        case .chromatic: return Array(0..<12)
        }
    }

    /// Whether a chord takes the minor form: it has a minor 3rd, or a 4th in its
    /// place (sus4), which the minor scales carry and the major ones clash with.
    static func isMinorFlavour(_ chord: Chord) -> Bool {
        let intervals = chord.quality.intervals
        return intervals.contains(3) || (intervals.contains(5) && !intervals.contains(4))
    }

    /// The pitch classes the plate plays, in `key`, with `chord` held (or none).
    func pitchClasses(in key: MajorKey, chord: Chord?) -> Set<Int>? {
        let root: Int
        let minor: Bool
        switch self {
        case .chord:
            return nil
        case .pentatonic, .blues:
            root = chord?.root ?? key.tonic
            minor = chord.map(Self.isMinorFlavour) ?? false
        case .naturalMinor:
            root = (key.tonic + 9) % 12
            minor = false
        case .major, .chromatic:
            root = key.tonic
            minor = false
        }
        guard let intervals = intervals(minor: minor) else { return nil }
        return Set(intervals.map { (root + $0) % 12 })
    }
}

/// How long a plucked plate note sounds before it is released (Graham, 2026-11-21: on
/// a synth, a note that rang until the next chord seemed to hang, since a synth keeps
/// sounding until it is released; a harp fades by itself). A note played again before
/// its time is struck afresh and timed from then.
///
/// While Held works like a keyboard (and like the instrument window's own keys): the
/// note sounds while the finger is on its string, and is released as the finger moves
/// off it or lifts, so the instrument's own release decides the tail.
nonisolated enum PlateRing: String, CaseIterable, Codable {
    case whileHeld, short, medium, long, untilChordChange

    var title: String {
        switch self {
        case .whileHeld: return "While Held"
        case .short: return "Short"
        case .medium: return "Medium"
        case .long: return "Long"
        case .untilChordChange: return "Until Chord"
        }
    }

    /// Seconds before the note is released; nil for While Held (released by the finger)
    /// and Until Chord.
    var seconds: Double? {
        switch self {
        case .whileHeld: return nil
        case .short: return 0.4
        case .medium: return 1.2
        case .long: return 3
        case .untilChordChange: return nil
        }
    }
}
