import Foundation
import CoreGraphics

/// The chord pads under the left hand. Graham's layout, 2026-11-20 (after first
/// playing: one pad is pressed at a time, so two plain rows):
///
/// ```
///  [ F ] [ C ] [ G ]          4  1  5
///  [Dm ] [Am ] [Em ]          2  6  3
///            [7th][sus2][sus4]   ← thumb
/// ```
///
/// The fingers play the chords, one at a time; the thumb holds the modifiers, below and
/// to the right of C (where Dm sat in the first layout). The key's diminished chord is
/// left out.
nonisolated enum ChordPad: String, CaseIterable, Codable {
    case four, one, five, two, six, three
    case seven, sus2, sus4

    /// The scale degree it plays, or nil for a modifier.
    var degree: Int? {
        switch self {
        case .four: return 4
        case .one: return 1
        case .five: return 5
        case .two: return 2
        case .six: return 6
        case .three: return 3
        case .seven, .sus2, .sus4: return nil
        }
    }

    var isModifier: Bool { degree == nil }

    /// The label in the corner of the pad.
    var degreeLabel: String {
        switch self {
        case .four: return "IV"
        case .one: return "I"
        case .five: return "V"
        case .two: return "ii"
        case .six: return "vi"
        case .three: return "iii"
        case .seven, .sus2, .sus4: return ""
        }
    }

    /// What a modifier pad says on its face.
    var modifierTitle: String? {
        switch self {
        case .seven: return "7th"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        default: return nil
        }
    }

    /// Where the pad sits, in pad-widths from the top left of the pad area.
    var gridPosition: CGPoint {
        switch self {
        case .four: return CGPoint(x: 0, y: 0)
        case .one: return CGPoint(x: 1.1, y: 0)
        case .five: return CGPoint(x: 2.2, y: 0)
        case .two: return CGPoint(x: 0, y: 1.1)
        case .six: return CGPoint(x: 1.1, y: 1.1)
        case .three: return CGPoint(x: 2.2, y: 1.1)
        // The thumb's row, smaller pads, centred where Dm sat relative to C before.
        case .seven: return CGPoint(x: 1.85, y: 2.35)
        case .sus2: return CGPoint(x: 2.7, y: 2.35)
        case .sus4: return CGPoint(x: 3.55, y: 2.35)
        }
    }

    /// Each pad's size as a share of a grid cell; the rest is the gap between pads.
    var sizeFraction: CGFloat { isModifier ? 0.78 : 0.94 }
}

/// Where each pad is drawn for a given space, and which pad a touch is on.
nonisolated struct PadLayout: Equatable {
    /// The whole arrangement, in pad-widths.
    static let gridSize = CGSize(width: 4.35, height: 3.15)

    let unit: CGFloat
    let origin: CGPoint

    /// The largest arrangement that fits, centred.
    init(size: CGSize) {
        let unit = max(0, min(size.width / Self.gridSize.width, size.height / Self.gridSize.height))
        self.unit = unit
        origin = CGPoint(x: (size.width - unit * Self.gridSize.width) / 2,
                         y: (size.height - unit * Self.gridSize.height) / 2)
    }

    func frame(of pad: ChordPad) -> CGRect {
        let side = unit * pad.sizeFraction
        let p = pad.gridPosition
        return CGRect(x: origin.x + p.x * unit, y: origin.y + p.y * unit, width: side, height: side)
    }

    func pad(at point: CGPoint) -> ChordPad? {
        ChordPad.allCases.first { frame(of: $0).contains(point) }
    }
}

/// Which pads are held, and so which chord the plate plays.
///
/// The most recently pressed chord pad wins; lift it and one still held takes over.
/// The modifiers are counted separately, so they work with any pad: the 7th adds the
/// 7th, sus2 or sus4 replaces the 3rd, and the 7th with a sus gives 7sus. With both
/// sus pads held, the last pressed counts.
nonisolated struct PadSelection: Equatable {
    /// Chord pads held, in the order they were pressed.
    private(set) var held: [ChordPad] = []
    private(set) var seventhHeld = false
    /// sus2 and sus4 held, in the order pressed.
    private(set) var suspensionsHeld: [ChordPad] = []

    var current: ChordPad? { held.last }

    var suspension: Suspension? {
        switch suspensionsHeld.last {
        case .sus2: return .second
        case .sus4: return .fourth
        default: return nil
        }
    }

    func isHeld(_ pad: ChordPad) -> Bool {
        switch pad {
        case .seven: return seventhHeld
        case .sus2, .sus4: return suspensionsHeld.contains(pad)
        default: return held.contains(pad)
        }
    }

    mutating func press(_ pad: ChordPad) {
        switch pad {
        case .seven: seventhHeld = true
        case .sus2, .sus4:
            suspensionsHeld.removeAll { $0 == pad }
            suspensionsHeld.append(pad)
        default:
            held.removeAll { $0 == pad }
            held.append(pad)
        }
    }

    mutating func release(_ pad: ChordPad) {
        switch pad {
        case .seven: seventhHeld = false
        case .sus2, .sus4: suspensionsHeld.removeAll { $0 == pad }
        default: held.removeAll { $0 == pad }
        }
    }

    mutating func releaseAll() {
        held.removeAll()
        seventhHeld = false
        suspensionsHeld.removeAll()
    }

    /// The chord a pad plays in `key` with the modifiers held now; nil for a modifier.
    func chord(on pad: ChordPad, in key: MajorKey) -> Chord? {
        guard let degree = pad.degree else { return nil }
        var chord = key.chord(degree: degree)
        if seventhHeld { chord = chord.withSeventh }
        if let suspension { chord = chord.suspended(suspension) }
        return chord
    }

    /// The chord to play in `key`, or nil when no chord pad is held.
    func chord(in key: MajorKey) -> Chord? {
        current.flatMap { chord(on: $0, in: key) }
    }
}
