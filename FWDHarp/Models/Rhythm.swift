import Foundation

/// The rhythm section (design brief, "Rhythm section"): drum styles to play along to,
/// each with a bass line that follows the chord pads, two variations, a fill and an
/// optional intro. Graham's first set, 2026-11-21.
///
/// Patterns are written one character per step on a bar's grid: sixteenths for the
/// straight styles, triplets for the shuffle. Drums: `.` rest, `g` ghost, `o` soft,
/// `x` normal, `X` accent. Bass: `.` rest, `-` holds the note before, and a note:
/// `R` the chord's root, `5` its fifth, `L` the fifth below the root, `O` the octave,
/// `3` the chord's third, `6` the sixth, `7` the chord's seventh (or the flat seventh).
nonisolated enum DrumVoice: Int, CaseIterable {
    // General MIDI drum notes, as the built-in drum kit and any GM kit plays them.
    case kick = 36, rim = 37, snare = 38, clap = 39, closedHat = 42, lowTom = 45, openHat = 46
    case midTom = 47, crash = 49, highTom = 50, ride = 51, tambourine = 54, cowbell = 56
    case highConga = 62, lowConga = 64, shaker = 70

    var note: UInt8 { UInt8(rawValue) }
}

/// One bar of a style: a line per drum, and the bass. An empty bass line plays the
/// style's main bass under a fill.
nonisolated struct RhythmBar: Equatable {
    let drums: [DrumVoice: String]
    let bass: String

    static func velocity(_ mark: Character) -> UInt8? {
        switch mark {
        case "g": return 40
        case "o": return 66
        case "x": return 96
        case "X": return 118
        default: return nil
        }
    }

    /// The drums struck at `step`, loudest first.
    func hits(at step: Int) -> [(note: UInt8, velocity: UInt8)] {
        drums.compactMap { voice, line in
            guard let mark = Self.mark(in: line, at: step), let velocity = Self.velocity(mark) else { return nil }
            return (voice.note, velocity)
        }
        // Loudest first; the same order every time (a dictionary has none of its own).
        .sorted { $0.velocity != $1.velocity ? $0.velocity > $1.velocity : $0.note < $1.note }
    }

    /// A bass note starting at `step`: which note of the chord, and for how many steps.
    func bassNote(at step: Int) -> (degree: Character, steps: Int)? {
        guard let mark = Self.mark(in: bass, at: step), mark != ".", mark != "-" else { return nil }
        let characters = Array(bass)
        var length = 1
        while step + length < characters.count, characters[step + length] == "-" { length += 1 }
        return (mark, length)
    }

    private static func mark(in line: String, at step: Int) -> Character? {
        let characters = Array(line)
        return characters.indices.contains(step) ? characters[step] : nil
    }
}

/// A bar read once into what the clock needs at each step, so playing it is a lookup:
/// the drums struck (loudest first) and the bass note starting, if any. Reading the
/// pattern's text on every step, as at first, made new arrays several times a step on
/// the clock's thread (code review, 2026-11-23).
nonisolated struct CompiledRhythmBar {
    let hits: [[(note: UInt8, velocity: UInt8)]]
    let bass: [(degree: Character, steps: Int)?]
    /// False for a fill without a bass line of its own: the main bar's bass plays.
    let hasBass: Bool

    init(_ bar: RhythmBar, steps: Int) {
        hits = (0..<steps).map { bar.hits(at: $0) }
        bass = (0..<steps).map { bar.bassNote(at: $0) }
        hasBass = !bar.bass.isEmpty
    }
}

/// Every bar of a style, read once.
nonisolated struct CompiledRhythmStyle {
    let a: CompiledRhythmBar
    let b: CompiledRhythmBar
    let fill: CompiledRhythmBar
    let intro: CompiledRhythmBar
    let outro: CompiledRhythmBar

    init(_ style: RhythmStyle) {
        let steps = style.stepsPerBar
        a = CompiledRhythmBar(style.bar(.a), steps: steps)
        b = CompiledRhythmBar(style.bar(.b), steps: steps)
        fill = CompiledRhythmBar(style.fill, steps: steps)
        intro = CompiledRhythmBar(style.intro, steps: steps)
        outro = CompiledRhythmBar(style.outro, steps: steps)
    }

    func bar(_ variation: RhythmVariation) -> CompiledRhythmBar { variation == .a ? a : b }
}

extension RhythmStyle {
    /// This style's bars, read once for the whole app the first time it is played.
    nonisolated var compiled: CompiledRhythmStyle { Self.compiledStyles[self]! }

    nonisolated private static let compiledStyles: [RhythmStyle: CompiledRhythmStyle] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, CompiledRhythmStyle($0)) })
}

nonisolated enum RhythmVariation: String, CaseIterable, Codable {
    case a, b
    var title: String { rawValue.uppercased() }
}

nonisolated enum RhythmStyle: String, CaseIterable, Codable {
    case rock, country, ballad, waltz, bossa, reggae, bluesShuffle, disco, rnb

    var title: String {
        switch self {
        case .rock: return "Rock / Pop"
        case .country: return "Country / Folk"
        case .ballad: return "Ballad"
        case .waltz: return "Waltz"
        case .bossa: return "Bossa Nova"
        case .reggae: return "Reggae"
        case .bluesShuffle: return "Blues Shuffle"
        case .disco: return "Dance / Disco"
        case .rnb: return "R&B"
        }
    }

    var beatsPerBar: Int { self == .waltz ? 3 : 4 }

    /// Steps in a beat: four sixteenths, or three triplets for the shuffle.
    var stepsPerBeat: Int { self == .bluesShuffle ? 3 : 4 }

    var stepsPerBar: Int { beatsPerBar * stepsPerBeat }

    /// A triplet feel: auto-strum's eighths swing to match (the second on the third
    /// triplet of the beat).
    var swings: Bool { stepsPerBeat == 3 }

    func bar(_ variation: RhythmVariation) -> RhythmBar {
        variation == .a ? patterns.a : patterns.b
    }

    var fill: RhythmBar { patterns.fill }
    var intro: RhythmBar { patterns.intro }

    /// The last bar, played when OUTRO is pressed: the next bar line starts it, and
    /// the final hit (crash, kick and the bass's root) lands on the bar after.
    var outro: RhythmBar {
        switch self {
        case .rock:
            return RhythmBar(drums: [.kick: "x.....x.x.......", .snare: "....X.......xxXX",
                                     .closedHat: "x.x.x.x.x.x....."],
                             bass: "R-R-R-R-5-5-O-O-")
        case .country:
            return RhythmBar(drums: [.kick: "x.......x.......", .snare: "gogoXogoXoXoXXXX"],
                             bass: "R---5---R---L---")
        case .ballad:
            return RhythmBar(drums: [.kick: "x.......x.......", .snare: "....x.......oxxx",
                                     .ride: "o.o.o.o.o.o....."],
                             bass: "R-------5---O---")
        case .waltz:
            return RhythmBar(drums: [.kick: "x...........", .snare: "....o...oxxX",
                                     .closedHat: "x...x......."],
                             bass: "R---5---O---")
        case .bossa:
            return RhythmBar(drums: [.kick: "x..x....x..x....", .rim: "x..x..x...x.x.x.",
                                     .closedHat: "o.o.o.o.o.o.o.o."],
                             bass: "R-----5-R-----5-")
        case .reggae:
            return RhythmBar(drums: [.kick: "........x.......", .rim: "........x.......",
                                     .closedHat: "x.x.x.x.x.x.....", .snare: "............xxxX"],
                             bass: "R-..R-..5-..O-..")
        case .bluesShuffle:
            return RhythmBar(drums: [.kick: "x.....x.....", .snare: "...X..xxx.xX",
                                     .closedHat: "x.xx.xx....."],
                             bass: "O..7..6..5..")
        case .disco:
            return RhythmBar(drums: [.kick: "x...x...x...x...", .clap: "....x.......xxxx",
                                     .openHat: "..o...o...o....."],
                             bass: "R-O-R-O-5-5-O-O-")
        case .rnb:
            return RhythmBar(drums: [.kick: "x......x..x.....", .snare: "....X.......xxXX",
                                     .closedHat: "xoxoxoxoxoxo...."],
                             bass: "R-----R-..5-O---")
        }
    }

    // swiftlint:disable function_body_length
    private var patterns: (a: RhythmBar, b: RhythmBar, fill: RhythmBar, intro: RhythmBar) {
        switch self {
        case .rock:
            return (
                RhythmBar(drums: [.kick: "x.......x.x.....", .snare: "....X.......X...",
                                  .closedHat: "x.x.x.x.x.x.x.x."],
                          bass: "R-R-R-R-R-R-R-R-"),
                RhythmBar(drums: [.kick: "x.....x.x.x.....", .snare: "....X.......X..o",
                                  .ride: "x.x.x.x.x.x.x.x."],
                          bass: "R-R-R-O-R-R-5-R-"),
                RhythmBar(drums: [.kick: "x.......x.......", .snare: "....X...xxxx....",
                                  .highTom: "............xx..", .lowTom: "..............xx",
                                  .closedHat: "x.x.x.x........."],
                          bass: ""),
                RhythmBar(drums: [.kick: "x.......x.......", .closedHat: "x...x...x...x...",
                                  .snare: "............oxxX"],
                          bass: "R---------------"))
        case .country:
            return (
                RhythmBar(drums: [.kick: "x.......x.......", .snare: "gogoXogogogoXogo"],
                          bass: "R-------5-------"),
                RhythmBar(drums: [.kick: "x.......x.......", .rim: "....x.......x...",
                                  .closedHat: "x.x.x.x.x.x.x.x."],
                          bass: "R---L---R---5---"),
                RhythmBar(drums: [.kick: "x.......x.......", .snare: "gogoXogoxxxxXxXx"],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...............", .snare: "gogogogogogoXxXx"],
                          bass: "R---------------"))
        case .ballad:
            return (
                RhythmBar(drums: [.kick: "x.......x.x.....", .rim: "....x.......x...",
                                  .closedHat: "o.o.o.o.o.o.o.o."],
                          bass: "R-------R---5---"),
                RhythmBar(drums: [.kick: "x.......x.x.....", .snare: "....x.......x...",
                                  .ride: "o.o.o.o.o.o.o.o."],
                          bass: "R-------5---O---"),
                RhythmBar(drums: [.kick: "x...............", .snare: "....x.......o.o.",
                                  .highTom: "........oo......", .lowTom: "..........oo...."],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...............", .ride: "o...o...o...o..."],
                          bass: "R---------------"))
        case .waltz:
            return (
                RhythmBar(drums: [.kick: "x...........", .snare: "....o...o...",
                                  .closedHat: "x...x...x..."],
                          bass: "R---........"),
                RhythmBar(drums: [.kick: "x...........", .rim: "....x...x...",
                                  .ride: "x.x.x.x.x.x."],
                          bass: "R---....5---"),
                RhythmBar(drums: [.kick: "x...........", .snare: "....o.o.xxxX",
                                  .lowTom: "..........xx"],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...........", .closedHat: "x...x...x...",
                                  .snare: "........oxxX"],
                          bass: "R-----------"))
        case .bossa:
            return (
                RhythmBar(drums: [.kick: "x..x....x..x....", .rim: "x..x..x...x..x..",
                                  .closedHat: "o.o.o.o.o.o.o.o."],
                          bass: "R-----5-R-----5-"),
                RhythmBar(drums: [.kick: "x..x....x..x....", .rim: "..x..x...x..x...",
                                  .shaker: "xoxoxoxoxoxoxoxo"],
                          bass: "R-----5-O-----5-"),
                RhythmBar(drums: [.kick: "x..x....x.......", .rim: "x..x..x.........",
                                  .highTom: "........x.x.....", .lowTom: "............x.x."],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...............", .rim: "x..x..x...x..x..",
                                  .closedHat: "o.o.o.o.o.o.o.o."],
                          bass: "R---------------"))
        case .reggae:
            return (
                RhythmBar(drums: [.kick: "........x.......", .rim: "........x.......",
                                  .closedHat: "x.x.x.x.x.x.x.x."],
                          bass: "R-..R-..5-..R-.."),
                RhythmBar(drums: [.kick: "x...x...x...x...", .rim: "........x.......",
                                  .closedHat: "..x...x...x...x."],
                          bass: "R-..R-R-5-..5-O-"),
                RhythmBar(drums: [.kick: "........x.......", .rim: "........x.......",
                                  .snare: "........x...xxxx"],
                          bass: ""),
                RhythmBar(drums: [.closedHat: "x.x.x.x.x.x.x.x.", .rim: "........x...x.x."],
                          bass: "R---------------"))
        case .bluesShuffle:
            return (
                RhythmBar(drums: [.kick: "x.....x.....", .snare: "...X.....X..",
                                  .closedHat: "x.xx.xx.xx.x"],
                          bass: "R.R3.35.56.6"),
                RhythmBar(drums: [.kick: "x.....x.....", .snare: "...X.....X..",
                                  .ride: "x.xx.xx.xx.x"],
                          bass: "R.R5.56.67.6"),
                RhythmBar(drums: [.kick: "x.....x.....", .snare: "...X..xxxxxX"],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...........", .closedHat: "x.xx.xx.xx.x",
                                  .snare: "......o.oxxX"],
                          bass: "R-----------"))
        case .disco:
            return (
                RhythmBar(drums: [.kick: "x...x...x...x...", .clap: "....x.......x...",
                                  .closedHat: "o...o...o...o...", .openHat: "..o...o...o...o."],
                          bass: "R-O-R-O-R-O-R-O-"),
                RhythmBar(drums: [.kick: "x...x...x...x...", .clap: "....x.......x...",
                                  .openHat: "..x...x...x...x.", .shaker: "gogogogogogogogo"],
                          bass: "R-O.R-O.R-O.5-O."),
                RhythmBar(drums: [.kick: "x...x...x...x...", .clap: "....x...x.x.xxxx"],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...x...x...x...", .closedHat: "o.o.o.o.o.o.o.o."],
                          bass: "................"))
        case .rnb:
            return (
                RhythmBar(drums: [.kick: "x......x..x.....", .snare: "....X.......X...",
                                  .closedHat: "xoxoxoxoxoxoxoxo"],
                          bass: "R-----R-..5-R---"),
                RhythmBar(drums: [.kick: "x..x...x..x..x..", .snare: "....X.......X...",
                                  .closedHat: "x.x.x.x.x.x.x...", .openHat: "..............x."],
                          bass: "R--R--5-..R-7-5-"),
                RhythmBar(drums: [.kick: "x......x........", .snare: "....X...x.xxxxXx"],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...............", .closedHat: "xoxoxoxoxoxoxoxo"],
                          bass: "R---------------"))
        }
    }
    // swiftlint:enable function_body_length
}

/// Where the bass plays a chord's notes.
nonisolated enum RhythmBass {
    /// The chord's root between E1 and D♯2, the bass guitar's lowest octave.
    static func root(of chord: Chord) -> Int {
        28 + ((chord.root - 4) % 12 + 12) % 12
    }

    /// The note for a pattern's mark, over `chord`.
    static func note(_ degree: Character, over chord: Chord) -> Int? {
        let root = root(of: chord)
        let intervals = chord.quality.intervals
        switch degree {
        case "R": return root
        case "5": return root + 7
        case "L": return root - 5
        case "O": return root + 12
        // The chord's own third; a sus chord's 2nd or 4th stands in for it.
        case "3": return root + (intervals.first { [3, 4, 2, 5].contains($0) } ?? 4)
        case "6": return root + 9
        case "7": return root + (intervals.contains(11) ? 11 : 10)
        default: return nil
        }
    }
}
