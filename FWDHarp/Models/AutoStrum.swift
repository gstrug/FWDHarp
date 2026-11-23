import Foundation

/// Auto-strum: with it on, pressing a chord pad sounds it, the app playing a pattern
/// in time in place of the strumming hand (design brief).
///
/// Every pattern plays from the plate's notes in straight order (the chord in the key
/// and octave chosen), so auto-strum and hand strumming sit in the same place. The
/// figure uses the plate's lowest strings: the chord once through plus the root on
/// top (C E G C; with the 7th, C E G B♭ C), or twice through for the 2-octave ones.
nonisolated enum AutoStrumPattern: String, CaseIterable, Codable {
    /// The rhythm style's own harp part (Graham, 2026-11-23), as an arranger keyboard's
    /// accompaniment comes with its style: oom-pah-pah for the waltz, off-beat chords
    /// for reggae and so on (RhythmBar.harp). It plays in the style's metre and feel
    /// whether or not the drums are running.
    case style
    case arpeggioUp, arpeggioDown, arpeggioUpDown
    case arpeggio2Up, arpeggio2Down, arpeggio2UpDown
    case blockChords, bassAndChord, singleSweep

    var title: String {
        switch self {
        case .style: return "Style"
        case .arpeggioUp: return "Arpeggio Up"
        case .arpeggioDown: return "Arpeggio Down"
        case .arpeggioUpDown: return "Arpeggio Up-Down"
        case .arpeggio2Up: return "2-Octave Up"
        case .arpeggio2Down: return "2-Octave Down"
        case .arpeggio2UpDown: return "2-Octave Up-Down"
        case .blockChords: return "Block Chords"
        case .bassAndChord: return "Bass + Chord"
        case .singleSweep: return "Single Sweep"
        }
    }

    /// How many steps make a beat: eighth notes for the arpeggios, one per beat for the
    /// chord patterns. The single sweep has no rhythm.
    var stepsPerBeat: Int {
        switch self {
        case .arpeggioUp, .arpeggioDown, .arpeggioUpDown,
             .arpeggio2Up, .arpeggio2Down, .arpeggio2UpDown: return 2
        case .blockChords, .bassAndChord: return 1
        // The style's own grid, sixteenths or triplets: the conductor steps it.
        case .style: return 4
        case .singleSweep: return 0
        }
    }

    var isRhythmic: Bool { stepsPerBeat > 0 }

    /// How many octaves an arpeggio spans.
    var octaves: Int {
        switch self {
        case .arpeggio2Up, .arpeggio2Down, .arpeggio2UpDown: return 2
        default: return 1
        }
    }
}

nonisolated enum AutoStrum {
    static let tempoRange: ClosedRange<Double> = 40...240
    static let defaultTempo: Double = 100
    /// Auto-strum plays at one steady loudness; hand strumming keeps the loudness
    /// across the plate.
    static let velocity: UInt8 = 96
    /// The gap between strings in a single sweep: a quick harp glissando.
    static let sweepGap: Double = 0.025

    /// The figure's notes: the chord `octaves` times through from the plate's bottom
    /// string, plus the next string (the root on top, for a chord in root position).
    static func figure(plateNotes: [Int], chordSize: Int, octaves: Int = 1) -> [Int] {
        Array(plateNotes.prefix(max(1, chordSize) * max(1, octaves) + 1))
    }

    /// The bass for Bass + Chord: the chord's root an octave below its lowest root on
    /// the plate, and the 5th above that bass (every chord the pads play has a 5th).
    static func bass(plateNotes: [Int], root: Int) -> (root: Int, fifth: Int)? {
        StrumPlate.bass(of: Chord(root: root, quality: .major), below: plateNotes)
    }

    /// An arpeggio with a pentatonic's colour (2026-11-23): between two chord notes a
    /// third to a fifth apart, the pentatonic note next to the second, leading into it
    /// (C D E G A C going up). A pentatonic's notes never clash with the chord, so they
    /// may fall anywhere; the round is kept to an even length, so the pattern lines up
    /// with the beat every time round instead of drifting across it (with an odd one,
    /// what was on the off-beat lands on the beat the next time).
    static func coloured(_ sequence: [Int], scale: Set<Int>) -> [Int] {
        guard sequence.count > 1 else { return sequence }
        var result: [Int] = []
        var lastPassing: Int?
        for (i, note) in sequence.enumerated() {
            result.append(note)
            let next = sequence[(i + 1) % sequence.count]
            let gap = next - note
            guard abs(gap) >= 3, abs(gap) <= 7 else { continue }
            // The scale note nearest `next` on this side of it.
            let step = gap > 0 ? -1 : 1
            if let passing = stride(from: next + step, to: note, by: step)
                .first(where: { scale.contains((($0 % 12) + 12) % 12) }) {
                lastPassing = result.count
                result.append(passing)
            }
        }
        if result.count % 2 == 1, let index = lastPassing { result.remove(at: index) }
        return result
    }

    /// The notes started at `step` (counted from 0 when the pattern starts). Each
    /// step's notes are released when the next step starts.
    static func notes(_ pattern: AutoStrumPattern, step: Int, plateNotes: [Int], chord: Chord,
                      scale: Set<Int>? = nil, beatsPerBar: Int = 4) -> [Int] {
        let steps = cycle(pattern, plateNotes: plateNotes, chord: chord, scale: scale, beatsPerBar: beatsPerBar)
        return steps.isEmpty ? [] : steps[step % steps.count]
    }

    /// Every step of the pattern for this chord, once round: the step played at `n` is
    /// `cycle[n % cycle.count]`. Worked out once when the chord changes, so each step is
    /// a lookup (code review, 2026-11-23). `scale`: a pentatonic's notes, for the
    /// arpeggios' passing notes (PlateScale.autoStrumColour); the chord patterns stay
    /// chords. `beatsPerBar`: 3 makes Bass + Chord an oom-pah-pah.
    static func cycle(_ pattern: AutoStrumPattern, plateNotes: [Int], chord: Chord,
                      scale: Set<Int>? = nil, beatsPerBar: Int = 4) -> [[Int]] {
        let figure = figure(plateNotes: plateNotes, chordSize: chord.pitchClasses.count,
                            octaves: pattern.octaves)
        guard !figure.isEmpty else { return [] }
        func arpeggio(_ sequence: [Int]) -> [[Int]] {
            (scale.map { coloured(sequence, scale: $0) } ?? sequence).map { [$0] }
        }
        switch pattern {
        case .arpeggioUp, .arpeggio2Up:
            return arpeggio(figure)
        case .arpeggioDown, .arpeggio2Down:
            return arpeggio(figure.reversed())
        case .arpeggioUpDown, .arpeggio2UpDown:
            // Up and back down without repeating the top and bottom: C E G C G E | C …
            return arpeggio(figure + figure.dropFirst().dropLast().reversed())
        case .blockChords:
            return [figure]
        case .bassAndChord:
            // Oom-pah: bass on 1 and 3 (root, then 5th), chord on 2 and 4. In 3/4 an
            // oom-pah-pah over two bars: root, chord, chord; 5th, chord, chord.
            guard let bass = bass(plateNotes: plateNotes, root: chord.root) else { return [figure] }
            let chordPart = Array(figure.dropLast())
            if beatsPerBar == 3 {
                return [[bass.root], chordPart, chordPart, [bass.fifth], chordPart, chordPart]
            }
            return [[bass.root], chordPart, [bass.fifth], chordPart]
        case .singleSweep, .style:
            return []
        }
    }
}

/// Tap tempo: the beat from the last few taps. A gap of over two seconds starts afresh.
nonisolated struct TapTempo: Equatable {
    static let resetGap: Double = 2
    static let tapsKept = 5
    private(set) var taps: [Double] = []

    /// Record a tap at `time` (seconds); returns the tempo once there are two taps.
    mutating func tap(at time: Double) -> Double? {
        if let last = taps.last, time - last > Self.resetGap || time <= last { taps.removeAll() }
        taps.append(time)
        if taps.count > Self.tapsKept { taps.removeFirst(taps.count - Self.tapsKept) }
        guard taps.count >= 2, let first = taps.first, let last = taps.last else { return nil }
        let beat = (last - first) / Double(taps.count - 1)
        guard beat > 0 else { return nil }
        let bpm = 60 / beat
        return min(max(bpm.rounded(), AutoStrum.tempoRange.lowerBound), AutoStrum.tempoRange.upperBound)
    }
}
