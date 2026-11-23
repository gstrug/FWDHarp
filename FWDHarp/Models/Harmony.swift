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
    /// The sus modifiers: the 3rd replaced by the 2nd or the 4th (Csus4 = C F G), so
    /// major and minor chords suspend alike.
    case suspendedSecond, suspendedFourth
    /// A sus modifier with the 7 (C7sus4 = C F G B♭).
    case seventhSuspendedSecond, seventhSuspendedFourth

    /// Semitones above the root.
    var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .diminished: return [0, 3, 6]
        case .dominantSeventh: return [0, 4, 7, 10]
        case .minorSeventh: return [0, 3, 7, 10]
        case .suspendedSecond: return [0, 2, 7]
        case .suspendedFourth: return [0, 5, 7]
        case .seventhSuspendedSecond: return [0, 2, 7, 10]
        case .seventhSuspendedFourth: return [0, 5, 7, 10]
        }
    }

    /// The quality with its 7th added, as the 7 modifier plays it: dominant 7ths on
    /// major chords, minor 7ths on minor ones (Graham: "the most common in Western
    /// music"). Already a 7th, or diminished: unchanged.
    var withSeventh: ChordQuality {
        switch self {
        case .major: return .dominantSeventh
        case .minor: return .minorSeventh
        case .suspendedSecond: return .seventhSuspendedSecond
        case .suspendedFourth: return .seventhSuspendedFourth
        default: return self
        }
    }

    /// The quality with its 3rd suspended, keeping any 7th.
    func suspended(_ suspension: Suspension) -> ChordQuality {
        let seventh = intervals.contains(10)
        switch suspension {
        case .second: return seventh ? .seventhSuspendedSecond : .suspendedSecond
        case .fourth: return seventh ? .seventhSuspendedFourth : .suspendedFourth
        }
    }

    var suffix: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .diminished: return "dim"
        case .dominantSeventh: return "7"
        case .minorSeventh: return "m7"
        case .suspendedSecond: return "sus2"
        case .suspendedFourth: return "sus4"
        case .seventhSuspendedSecond: return "7sus2"
        case .seventhSuspendedFourth: return "7sus4"
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

    /// This chord with its 3rd suspended (see ChordQuality.suspended).
    func suspended(_ suspension: Suspension) -> Chord {
        Chord(root: root, quality: quality.suspended(suspension))
    }
}

/// Which note replaces a chord's 3rd: the 2nd (sus2) or the 4th (sus4).
nonisolated enum Suspension: String, Codable {
    case second, fourth
}

nonisolated enum NoteNames {
    private static let sharps = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let flats = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    static func name(_ pitchClass: Int, preferFlats: Bool) -> String {
        let pc = ((pitchClass % 12) + 12) % 12
        return preferFlats ? flats[pc] : sharps[pc]
    }
}

/// The key the pads play in: a major key, or (Graham, 2026-11-23) a minor one.
///
/// A minor key's chords are its natural minor's, with one change every song book makes:
/// the 5 is MAJOR (E in A minor, the harmonic minor's), because that is the chord that
/// leads home. The pads mirror the major layout: the key's own chords on top (iv i V),
/// their relatives underneath (VI III VII), so A minor's pads are the same as C major's
/// with the rows swapped (and E for Em). See ChordPad.
nonisolated struct MusicKey: Equatable, Codable, Hashable {
    /// Pitch class of the tonic, 0 = C … 11 = B.
    var tonic: Int
    var isMinor: Bool

    init(tonic: Int, minor: Bool = false) {
        self.tonic = tonic
        self.isMinor = minor
    }

    private static let majorSteps = [0, 2, 4, 5, 7, 9, 11]
    private static let majorQualities: [ChordQuality] = [.major, .minor, .minor, .major, .major, .minor, .diminished]
    private static let minorSteps = [0, 2, 3, 5, 7, 8, 10]
    private static let minorQualities: [ChordQuality] = [.minor, .diminished, .major, .minor, .minor, .major, .major]

    /// The chord on scale degree 1–7 of the key's own scale (natural minor for a minor
    /// key: its 5 is minor here; the 5 pad plays it major, see ChordPad).
    func chord(degree: Int) -> Chord {
        let i = ((degree - 1) % 7 + 7) % 7
        let steps = isMinor ? Self.minorSteps : Self.majorSteps
        let qualities = isMinor ? Self.minorQualities : Self.majorQualities
        return Chord(root: (tonic + steps[i]) % 12, quality: qualities[i])
    }

    /// The key's scale: major, or natural minor.
    var scale: Set<Int> {
        Set((isMinor ? Self.minorSteps : Self.majorSteps).map { (tonic + $0) % 12 })
    }

    /// The key's home chord.
    var tonicChord: Chord { Chord(root: tonic, quality: isMinor ? .minor : .major) }

    /// Keys written with flats name their chords with flats: F, B♭, E♭, A♭, D♭ major,
    /// and the minor keys that share their notes (D, G, C, F, B♭ minor).
    var prefersFlats: Bool {
        let major = isMinor ? (tonic + 3) % 12 : tonic
        return [5, 10, 3, 8, 1].contains(major)
    }

    /// "C", "Am": as on the KEY button.
    var name: String { NoteNames.name(tonic, preferFlats: prefersFlats) + (isMinor ? "m" : "") }

    /// "C major", "A minor": as in the KEY menu.
    var fullName: String { NoteNames.name(tonic, preferFlats: prefersFlats) + (isMinor ? " minor" : " major") }

    /// The twelve major keys, C to B, then the twelve minor keys, for the key button.
    static let all: [MusicKey] = (0..<12).map { MusicKey(tonic: $0) }
        + (0..<12).map { MusicKey(tonic: ($0 + 9) % 12, minor: true) }

    // A key saved before minor keys existed has only a tonic.
    private enum CodingKeys: String, CodingKey { case tonic, isMinor }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tonic = try c.decode(Int.self, forKey: .tonic)
        isMinor = try c.decodeIfPresent(Bool.self, forKey: .isMinor) ?? false
    }
}
