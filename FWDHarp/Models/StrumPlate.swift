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
    static func lowestNote(in key: MusicKey, octaveShift: Int = 0) -> Int {
        48 + key.tonic + 12 * octaveShift
    }

    /// The note on each string, bottom string first: the chord's notes in order,
    /// starting from the first one at or above `lowest`.
    static func notes(for chord: Chord, strings: Int, from lowest: Int) -> [Int] {
        notes(pitchClasses: Set(chord.pitchClasses), strings: strings, from: lowest)
    }

    /// The notes of a set of pitch classes in order up from `lowest`, one per string.
    /// Where the chord's root first comes in `tones` (the plate may start on its 3rd
    /// or 5th): a Custom figure counts its steps from there, so 1 is always the root.
    private static func rootIndex(of chord: Chord, in tones: [Int]) -> Int {
        tones.prefix(chord.pitchClasses.count).firstIndex { $0 % 12 == chord.root } ?? 0
    }

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
    static func notes(for chord: Chord, strings: Int, from lowest: Int, pattern: PlatePattern,
                      custom: [Int] = PlatePattern.defaultCustom) -> [Int] {
        // Enough of the straight run for every pattern to look ahead into.
        // Custom can climb faster than one chord note a string (a figure of one step
        // climbs a round per string), so it gets a run long enough for any figure.
        let run = pattern == .custom ? strings * chord.pitchClasses.count + 8 : strings * 2 + 4
        let tones = notes(for: chord, strings: run, from: lowest)
        return ordered(tones, strings: strings, pattern: pattern, bass: bass(of: chord, below: tones),
                       custom: custom, chordSize: chord.pitchClasses.count, rootAt: rootIndex(of: chord, in: tones))
    }

    /// Everything on the plate, bottom string first: `scale`'s notes, or (with Chord)
    /// the chord held in the plate pattern's order; none with no chord held.
    ///
    /// Centred (Graham, 2026-11-25): from the key's note in octave 3 (moved by OCT) a
    /// long plate (20 or 24 strings) or a sparse Custom figure ran past the top of
    /// MIDI and its top strings were silent. The bottom now drops by whole octaves
    /// until every string has a note and the plate's middle is within an octave of a
    /// 3-octave plate's middle (or as near as it can get). The drop is worked out on the key's own chord, so
    /// it is the same for every chord and the plate never jumps an octave on a chord
    /// change. Plates that already fit (10, 13 and 16 strings of a chord, and the
    /// scales) stay where they were.
    static func plate(chord: Chord?, key: MusicKey, scale: PlateScale, strings: Int, octaveShift: Int,
                      pattern: PlatePattern, custom: [Int]) -> [Int] {
        func build(_ chord: Chord?, from bottom: Int) -> [Int] {
            if scale != .chord {
                return notes(for: scale, in: key, chord: chord, strings: strings, from: bottom, pattern: pattern)
            }
            guard let chord else { return [] }
            return notes(for: chord, strings: strings, from: bottom, pattern: pattern, custom: custom)
        }
        let usual = lowestNote(in: key, octaveShift: octaveShift)
        let target = Double(usual + 18)
        var bestDrop = 0
        var bestScore = Double.infinity
        for drop in 0...max(0, usual / 12) {
            let notes = build(key.tonicChord, from: usual - 12 * drop)
            guard let low = notes.min(), let high = notes.max() else { continue }
            let missing = Double(strings - notes.count)
            let offCentre = abs(Double(low + high) / 2 - target)
            // The highest plate that is full and within an octave of the middle: the
            // usual place unless it does not fit.
            if missing == 0, offCentre <= 12 { return build(chord, from: usual - 12 * drop) }
            let score = missing * 1000 + offCentre
            if score < bestScore { bestScore = score; bestDrop = drop }
        }
        return build(chord, from: usual - 12 * bestDrop)
    }

    /// A scale on the plate (PlateScale), one note per string up from the chord's first
    /// note at or above the plate's bottom (the key's note, moved by OCT), in the plate
    /// pattern's order. Every scale follows `chord`, the one held now. Bass + Chord has
    /// no chord to take a bass from, and Custom is a figure of chord notes, so both play
    /// Straight.
    static func notes(for scale: PlateScale, in key: MusicKey, chord: Chord?, strings: Int,
                      octaveShift: Int, pattern: PlatePattern) -> [Int] {
        notes(for: scale, in: key, chord: chord, strings: strings,
              from: lowestNote(in: key, octaveShift: octaveShift), pattern: pattern)
    }

    static func notes(for scale: PlateScale, in key: MusicKey, chord: Chord?, strings: Int,
                      from bottom: Int, pattern: PlatePattern) -> [Int] {
        guard let classes = scale.pitchClasses(in: key, chord: chord) else { return [] }
        // The bottom string is one of the chord's notes, as in Chord mode: the first at
        // or above the plate's bottom, so a scale never starts on a clash (2026-11-23).
        let home = Set((chord ?? key.tonicChord).pitchClasses)
        // Chromatic stays put on the key's note: a tune's notes must not move when the
        // chord changes (2026-11-25).
        let start = scale == .chromatic ? bottom
            : (bottom..<(bottom + 12)).first { home.contains($0 % 12) } ?? bottom
        let tones = notes(pitchClasses: classes, strings: strings * 2 + 4, from: start)
        let chordOnly: Set<PlatePattern> = [.bassAndChord, .custom]
        return ordered(tones, strings: strings, pattern: chordOnly.contains(pattern) ? .straight : pattern,
                       bass: nil)
    }

    /// The straight run `tones` put in a plate pattern's order, one note per string.
    private static func ordered(_ tones: [Int], strings: Int, pattern: PlatePattern,
                                bass: (root: Int, fifth: Int)?,
                                custom: [Int] = PlatePattern.defaultCustom, chordSize: Int = 3,
                                rootAt: Int = 0) -> [Int] {
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
        case .custom:
            // Your own figure, round and round up the plate, each round an octave of
            // chord notes higher: 1 5 3 8 | 8 12 10 15 …
            // The first step is the figure's lowest note, and any step below it goes
            // up an octave, so 5 1 3 and 3 5 1 play as inversions (G C E, E G C) —
            // Graham, 2026-11-25. Each round starts as low on the plate as it can.
            let figure = custom.isEmpty ? PlatePattern.defaultCustom : custom
            let first = PlatePattern.chordNote(figure[0], chordSize: chordSize)
            var start = rootAt + first
            while start - chordSize >= 0 { start -= chordSize }
            result = (0..<strings).map { index in
                let round = index / figure.count
                var step = PlatePattern.chordNote(figure[index % figure.count], chordSize: chordSize)
                if step < first { step += chordSize }
                return tone(start + round * chordSize + step - first)
            }
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
    /// Your own figure of chord notes (Graham, 2026-11-25), such as 1 5 3 8, repeated up
    /// the plate. Starts as a three-note arpeggio, 1 3 5.
    case custom

    var title: String {
        switch self {
        case .straight: return "Straight"
        case .alternating: return "Alternating"
        case .rolling: return "Rolling"
        case .octaves: return "Octaves"
        case .bassAndChord: return "Bass + Chord"
        case .custom: return "Custom"
        }
    }

    /// A custom figure's steps: 1 the root, 3 the chord's 3rd (or the 2nd or 4th of a
    /// sus chord), 5 its 5th, 7 its 7th (the octave when it has none), 8 the octave.
    static let customSteps = [1, 3, 5, 7, 8]
    static let defaultCustom = [1, 3, 5]
    static let customLength = 1...8

    /// Which of the chord's notes, counted from its root, a step is.
    static func chordNote(_ step: Int, chordSize: Int) -> Int {
        switch step {
        case 1: return 0
        case 3: return 1
        case 5: return 2
        case 7: return chordSize > 3 ? 3 : chordSize
        default: return chordSize
        }
    }

    /// A figure as written: "1 5 3 8".
    static func describe(_ figure: [Int]) -> String {
        figure.map(String.init).joined(separator: " ")
    }

    /// A figure kept to the steps and length allowed; anything else becomes 1 3 5.
    static func normalized(_ figure: [Int]) -> [Int] {
        let kept = figure.filter(customSteps.contains)
        return customLength.contains(kept.count) ? kept : defaultCustom
    }
}

/// What the plate plays: the held chord's notes (the default), or a scale, which
/// gives the plate more notes for melody. A scale plays whether or not a pad is held
/// (with none held, over the key's home chord).
///
/// Every scale FOLLOWS THE CHORD held, so whatever a non-musician strums sounds good
/// (Graham, 2026-11-23, after Major, Natural Minor and Chromatic sounded off). The way
/// arranger keyboards and jazz players do it: a scale's notes over a chord, less its
/// "avoid notes", the ones that clash with the chord (a semitone above one of its
/// notes, like F over C). See `fitted`.
/// - Melody: the key's notes that fit the chord (over C in C: C D E G A B).
/// - Pentatonic: the chord's own pentatonic, major over a major chord (C D E G A),
///   minor over a minor or sus4 one (A C D E G).
/// - Minor Pentatonic: the key's minor pentatonic (in C, A minor's: A C D E G; in
///   A minor the same), the classic rock and blues lead, fitted to each chord.
/// - Blues: over a major chord 1 2 3 5 6 ♭7 (the bluesy flat 7th, without the ♭3 that
///   rubbed against the chord's 3rd); over a minor one the minor blues, 1 ♭3 4 ♭5 5 ♭7.
///
/// - Chromatic: every note, for playing tunes note by note. It does NOT follow the
///   chord, so half its strings clash with it: back by Graham's wish (2026-11-25), for
///   melodies, knowing that.
///
/// Natural Minor was taken out (2026-11-23): it was the same notes as Major. A setup
/// saved with it opens on Chord.
nonisolated enum PlateScale: String, CaseIterable, Codable {
    case chord
    /// Saved as "major", from when it was the key's whole major scale.
    case major
    case pentatonic, minorPentatonic, blues, chromatic

    var title: String {
        switch self {
        case .chord: return "Chord"
        case .major: return "Melody"
        case .pentatonic: return "Pentatonic"
        case .minorPentatonic: return "Minor Pentatonic"
        case .blues: return "Blues"
        case .chromatic: return "Chromatic"
        }
    }

    /// Whether a chord takes the minor form: it has a minor 3rd, or a 4th in its
    /// place (sus4), which the minor scales carry and the major ones clash with.
    static func isMinorFlavour(_ chord: Chord) -> Bool {
        let intervals = chord.quality.intervals
        return intervals.contains(3) || (intervals.contains(5) && !intervals.contains(4))
    }

    /// The pitch classes the plate plays, in `key`, with `chord` held (none: the key's
    /// home chord). Nil for Chord.
    func pitchClasses(in key: MusicKey, chord: Chord?) -> Set<Int>? {
        let chord = chord ?? key.tonicChord
        func on(_ root: Int, _ intervals: [Int]) -> Set<Int> { Set(intervals.map { (root + $0) % 12 }) }
        let minor = Self.isMinorFlavour(chord)
        switch self {
        case .chord:
            return nil
        case .major:
            return Self.fitted(key.scale, to: chord, in: key)
        case .pentatonic:
            return on(chord.root, minor ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9])
        case .minorPentatonic:
            // The key's minor: its own tonic, or a major key's relative minor.
            let root = key.isMinor ? key.tonic : (key.tonic + 9) % 12
            return Self.fitted(on(root, [0, 3, 5, 7, 10]), to: chord, in: key)
        case .blues:
            return on(chord.root, minor ? [0, 3, 5, 6, 7, 10] : [0, 2, 4, 7, 9, 10])
        case .chromatic:
            return Set(0..<12)
        }
    }

    /// `scale` over `chord`, with the notes that clash taken out and the chord's own
    /// notes always in:
    /// - a note a semitone above a chord note (the classic avoid note: F over C,
    ///   C over G, F over Am and Em);
    /// - a note a semitone below a chord note the key does not have (G under the G♯
    ///   of E major in A minor; B under the B♭ of C7);
    /// - with a sus4 chord, its missing 3rd, which the 4th replaced.
    static func fitted(_ scale: Set<Int>, to chord: Chord, in key: MusicKey) -> Set<Int> {
        let tones = Set(chord.pitchClasses)
        let keyNotes = key.scale
        var result = scale.filter { note in
            if tones.contains((note + 11) % 12) { return false }
            let above = (note + 1) % 12
            if tones.contains(above), !keyNotes.contains(above) { return false }
            return true
        }
        let intervals = chord.quality.intervals
        if intervals.contains(5), !intervals.contains(4), !intervals.contains(3) {
            result.remove((chord.root + 3) % 12)
            result.remove((chord.root + 4) % 12)
        }
        return result.union(tones)
    }

    /// The passing notes auto-strum's arpeggios may take (Graham, 2026-11-23): only the
    /// pentatonics', which never clash, and only on the off-beats (AutoStrum.cycle).
    /// Every other scale leaves auto-strum on the chord's own notes, as an arranger
    /// keyboard's chord parts are.
    func autoStrumColour(in key: MusicKey, chord: Chord?) -> Set<Int>? {
        switch self {
        case .pentatonic, .minorPentatonic: return pitchClasses(in: key, chord: chord)
        case .chord, .major, .blues, .chromatic: return nil
        }
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

/// What sliding a held finger sideways on the plate does (Graham, 2026-11-23). A note's
/// MIDI velocity is fixed when it starts, so the slide sends a control the instrument
/// keeps listening to, measured from where the finger landed (nothing moves at the
/// touch). The plate's whole channel follows the finger that moved last.
nonisolated enum PlateSlide: String, CaseIterable, Codable {
    /// Expression (controller 11): louder to the right, softer to the left. A quick
    /// wobble gives a tremolo, a slow slide a swell.
    case expression
    /// The mod wheel (controller 1): more the further the finger slides either way.
    case modWheel
    /// Pitch bend: a wobble is a vibrato, a slide a bend (right up, left down).
    case pitchBend
    /// Channel aftertouch: more the further the finger slides either way.
    case aftertouch
    case off

    var title: String {
        switch self {
        case .expression: return "Expression (volume)"
        case .modWheel: return "Mod Wheel"
        case .pitchBend: return "Pitch Bend (vibrato)"
        case .aftertouch: return "Aftertouch"
        case .off: return "Off"
        }
    }

    /// The message for a finger that has slid `slide` plate-widths from where it
    /// landed (−1 … 1, right positive), as status and two data bytes (aftertouch uses
    /// only the first). Nil for Off.
    func message(slide: Double, depth: SlideDepth) -> (status: UInt8, data1: UInt8, data2: UInt8)? {
        func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Int {
            Int(min(max(value, range.lowerBound), range.upperBound).rounded())
        }
        switch self {
        case .expression:
            let value = clamp(Double(Self.landingExpression) + slide * depth.controllerSpan, 20...127)
            return (0xB0, 11, UInt8(value))
        case .modWheel:
            return (0xB0, 1, UInt8(clamp(abs(slide) * depth.controllerSpan, 0...127)))
        case .aftertouch:
            return (0xD0, UInt8(clamp(abs(slide) * depth.controllerSpan, 0...127)), 0)
        case .pitchBend:
            let value = clamp(8192 + slide * depth.bendSpan, 0...16383)
            return (0xE0, UInt8(value & 0x7F), UInt8(value >> 7))
        case .off:
            return nil
        }
    }

    /// Where a finger landing leaves it: no slide.
    func resting(depth: SlideDepth) -> (status: UInt8, data1: UInt8, data2: UInt8)? {
        message(slide: 0, depth: depth)
    }

    /// The control set back to the instrument's own default, for PANIC or when the
    /// slide is switched to another control: full expression, no modulation, no bend.
    var reset: (status: UInt8, data1: UInt8, data2: UInt8)? {
        switch self {
        case .expression: return (0xB0, 11, 127)
        case .modWheel: return (0xB0, 1, 0)
        case .aftertouch: return (0xD0, 0, 0)
        case .pitchBend: return (0xE0, 0, 64)
        case .off: return nil
        }
    }

    /// Expression where a finger lands: a little under full, so a slide right can
    /// still swell.
    static let landingExpression: UInt8 = 100
}

/// How strongly the slide acts.
nonisolated enum SlideDepth: String, CaseIterable, Codable {
    case subtle, medium, strong

    var title: String { rawValue.capitalized }

    /// Controller steps (of 127) for a slide across the whole plate.
    var controllerSpan: Double {
        switch self {
        case .subtle: return 150
        case .medium: return 300
        case .strong: return 600
        }
    }

    /// Pitch bend steps (of 8192 each way) for a slide across the whole plate. Most
    /// instruments bend 2 semitones at full, so Medium's small wobble is a gentle vibrato.
    var bendSpan: Double {
        switch self {
        case .subtle: return 3000
        case .medium: return 8000
        case .strong: return 16000
        }
    }
}
