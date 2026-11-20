import Foundation

/// The chords of a major key, for the chord pads. Pure and portable, so it is tested
/// by `swift test` (Package.swift), like FWD Sequencer's core.
///
/// Degrees are 1–7 of the major scale: 1, 4 and 5 major; 2, 3 and 6 minor; 7
/// diminished. The pads show 1–6 (design brief, 2026-11-20; see Pads.swift); the 7
/// pad is a modifier that adds each chord's 7th.
nonisolated enum ChordQuality: String, Codable, CaseIterable {
    case major, minor, diminished
    /// The 7 modifier on a major chord: the song-book 7th (C7 = C E G B♭).
    case dominantSeventh
    /// The 7 modifier on a minor chord (Am7 = A C E G).
    case minorSeventh

    /// Semitones above the root.
    var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .diminished: return [0, 3, 6]
        case .dominantSeventh: return [0, 4, 7, 10]
        case .minorSeventh: return [0, 3, 7, 10]
        }
    }

    /// The quality with its 7th added, as the 7 modifier plays it: dominant 7ths on
    /// major chords, minor 7ths on minor ones (Graham: "the most common in Western
    /// music"). Already a 7th, or diminished: unchanged.
    var withSeventh: ChordQuality {
        switch self {
        case .major: return .dominantSeventh
        case .minor: return .minorSeventh
        case .diminished, .dominantSeventh, .minorSeventh: return self
        }
    }

    var suffix: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .diminished: return "dim"
        case .dominantSeventh: return "7"
        case .minorSeventh: return "m7"
        }
    }
}

nonisolated struct Chord: Equatable, Codable {
    /// Pitch class of the root, 0 = C … 11 = B.
    var root: Int
    var quality: ChordQuality

    /// The chord's pitch classes, root first.
    var pitchClasses: [Int] { quality.intervals.map { (root + $0) % 12 } }

    func name(preferFlats: Bool) -> String {
        NoteNames.name(root, preferFlats: preferFlats) + quality.suffix
    }

    /// This chord with its 7th added (see ChordQuality.withSeventh).
    var withSeventh: Chord { Chord(root: root, quality: quality.withSeventh) }
}

nonisolated enum NoteNames {
    private static let sharps = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let flats = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    static func name(_ pitchClass: Int, preferFlats: Bool) -> String {
        let pc = ((pitchClass % 12) + 12) % 12
        return preferFlats ? flats[pc] : sharps[pc]
    }
}

nonisolated struct MajorKey: Equatable, Codable {
    /// Pitch class of the tonic, 0 = C … 11 = B.
    var tonic: Int

    private static let steps = [0, 2, 4, 5, 7, 9, 11]
    private static let qualities: [ChordQuality] = [.major, .minor, .minor, .major, .major, .minor, .diminished]

    /// The chord on scale degree 1–7.
    func chord(degree: Int) -> Chord {
        let i = ((degree - 1) % 7 + 7) % 7
        return Chord(root: (tonic + Self.steps[i]) % 12, quality: Self.qualities[i])
    }

    /// Keys written with flats (F, B♭, E♭, A♭, D♭) name their chords with flats.
    var prefersFlats: Bool { [5, 10, 3, 8, 1].contains(tonic) }

    var name: String { NoteNames.name(tonic, preferFlats: prefersFlats) }

    /// The twelve keys, C to B, for the key button.
    static let all: [MajorKey] = (0..<12).map { MajorKey(tonic: $0) }
}
