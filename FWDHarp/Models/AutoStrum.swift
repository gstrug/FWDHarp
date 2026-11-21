import Foundation

/// Auto-strum: with it on, pressing a chord pad sounds it, the app playing a pattern
/// in time in place of the strumming hand (design brief).
///
/// Every pattern plays from the plate's notes in straight order (the chord in the key
/// and octave chosen), so auto-strum and hand strumming sit in the same place. The
/// figure uses the plate's lowest strings: the chord once through plus the root on
/// top (C E G C; with the 7th, C E G B♭ C), or twice through for the 2-octave ones.
nonisolated enum AutoStrumPattern: String, CaseIterable, Codable {
    case arpeggioUp, arpeggioDown, arpeggioUpDown
    case arpeggio2Up, arpeggio2Down, arpeggio2UpDown
    case blockChords, bassAndChord, singleSweep

    var title: String {
        switch self {
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

    /// The notes started at `step` (counted from 0 when the pattern starts). Each
    /// step's notes are released when the next step starts.
    static func notes(_ pattern: AutoStrumPattern, step: Int, plateNotes: [Int], chord: Chord) -> [Int] {
        let figure = figure(plateNotes: plateNotes, chordSize: chord.pitchClasses.count,
                            octaves: pattern.octaves)
        guard !figure.isEmpty else { return [] }
        switch pattern {
        case .arpeggioUp, .arpeggio2Up:
            return [figure[step % figure.count]]
        case .arpeggioDown, .arpeggio2Down:
            let down = Array(figure.reversed())
            return [down[step % down.count]]
        case .arpeggioUpDown, .arpeggio2UpDown:
            // Up and back down without repeating the top and bottom: C E G C G E | C …
            let cycle = figure + figure.dropFirst().dropLast().reversed()
            return [cycle[step % cycle.count]]
        case .blockChords:
            return figure
        case .bassAndChord:
            // Oom-pah: bass on beats 1 and 3 (root, then 5th), chord on 2 and 4.
            guard let bass = bass(plateNotes: plateNotes, root: chord.root) else { return figure }
            switch step % 4 {
            case 0: return [bass.root]
            case 2: return [bass.fifth]
            default: return Array(figure.dropLast())
            }
        case .singleSweep:
            return []
        }
    }

    /// Seconds between steps at `tempo` beats a minute.
    static func stepInterval(_ pattern: AutoStrumPattern, tempo: Double) -> Double {
        guard pattern.isRhythmic else { return 0 }
        let bpm = min(max(tempo, tempoRange.lowerBound), tempoRange.upperBound)
        return 60 / bpm / Double(pattern.stepsPerBeat)
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
