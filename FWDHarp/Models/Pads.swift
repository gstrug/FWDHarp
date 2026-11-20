import Foundation
import CoreGraphics

/// The chord pads under the left hand (design brief, 2026-11-20):
///
/// ```
///  pinky   ring   middle  index
///  [ 7 ]  [ 4 ]   [ 1 ]  [ 5 ]
///                 thumb: [ 6 ] [ 3 ]
///                           [ 2 ]
/// ```
///
/// One finger per pad, no reaching: 4 1 5 under ring, middle and index; the minor
/// chords under the thumb; the 7 under the pinky is not a chord but a modifier that
/// adds the 7th while held. The key's diminished chord is left out.
nonisolated enum ChordPad: String, CaseIterable, Codable {
    case seven, four, one, five, six, three, two

    /// The scale degree it plays, or nil for the 7 modifier.
    var degree: Int? {
        switch self {
        case .seven: return nil
        case .four: return 4
        case .one: return 1
        case .five: return 5
        case .six: return 6
        case .three: return 3
        case .two: return 2
        }
    }

    var isModifier: Bool { self == .seven }

    /// The label in the corner of the pad.
    var degreeLabel: String {
        switch self {
        case .seven: return "7"
        case .four: return "IV"
        case .one: return "I"
        case .five: return "V"
        case .six: return "vi"
        case .three: return "iii"
        case .two: return "ii"
        }
    }

    /// Where the pad sits, in pad-widths from the top left of the pad area. The finger
    /// row is arched like a resting hand: the middle finger reaches furthest, the
    /// pinky least.
    var gridPosition: CGPoint {
        switch self {
        case .seven: return CGPoint(x: 0, y: 0.40)
        case .four: return CGPoint(x: 1.1, y: 0.12)
        case .one: return CGPoint(x: 2.2, y: 0)
        case .five: return CGPoint(x: 3.3, y: 0.18)
        case .six: return CGPoint(x: 3.3, y: 1.45)
        case .three: return CGPoint(x: 4.4, y: 1.45)
        case .two: return CGPoint(x: 3.85, y: 2.6)
        }
    }
}

/// Where each pad is drawn for a given space, and which pad a touch is on.
nonisolated struct PadLayout: Equatable {
    /// The whole arrangement, in pad-widths.
    static let gridSize = CGSize(width: 5.4, height: 3.6)
    /// Each pad's size as a share of a grid cell; the rest is the gap between pads.
    static let padFraction: CGFloat = 0.94

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
        let side = unit * Self.padFraction
        let p = pad.gridPosition
        return CGRect(x: origin.x + p.x * unit, y: origin.y + p.y * unit, width: side, height: side)
    }

    func pad(at point: CGPoint) -> ChordPad? {
        ChordPad.allCases.first { frame(of: $0).contains(point) }
    }
}

/// Which pads are held, and so which chord the plate plays.
///
/// The most recently pressed chord pad wins; lift it and the one still held before it
/// takes over. The 7 modifier is counted separately, so it works with any pad.
nonisolated struct PadSelection: Equatable {
    /// Chord pads held, in the order they were pressed.
    private(set) var held: [ChordPad] = []
    private(set) var seventhHeld = false

    var current: ChordPad? { held.last }

    mutating func press(_ pad: ChordPad) {
        if pad.isModifier { seventhHeld = true; return }
        held.removeAll { $0 == pad }
        held.append(pad)
    }

    mutating func release(_ pad: ChordPad) {
        if pad.isModifier { seventhHeld = false; return }
        held.removeAll { $0 == pad }
    }

    mutating func releaseAll() {
        held.removeAll()
        seventhHeld = false
    }

    /// The chord to play in `key`, or nil when no chord pad is held.
    func chord(in key: MajorKey) -> Chord? {
        guard let degree = current?.degree else { return nil }
        let chord = key.chord(degree: degree)
        return seventhHeld ? chord.withSeventh : chord
    }
}
