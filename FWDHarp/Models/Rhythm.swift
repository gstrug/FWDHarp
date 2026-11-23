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
/// Harp (auto-strum's Style pattern, 2026-11-23): `.` lets go, `-` lets it ring, `c` the
/// chord (the plate's lowest chord notes and the root on top), `C` the chord accented,
/// `u` the chord without its bottom note (a light upper chord), `R` and `5` a bass note
/// below the chord (root, fifth), `1`–`4` one note of the chord, bottom up.
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
    /// Auto-strum's harp part in the Style pattern. Empty: the main bar's plays (fills).
    var harp: String = ""

    func with(harp: String) -> RhythmBar {
        RhythmBar(drums: drums, bass: bass, harp: harp)
    }

    /// What the harp does at `step`; nil for a rest (or past the end).
    func harpMark(at step: Int) -> HarpMark? {
        guard let mark = Self.mark(in: harp, at: step) else { return nil }
        return HarpMark(mark)
    }

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

/// One step of a style's harp part.
nonisolated enum HarpMark: Equatable {
    case hold
    case chord(accent: Bool)
    case upperChord
    case bassRoot, bassFifth
    /// One chord note, 0 the bottom one.
    case note(Int)

    /// Nil for `.`, a rest.
    init?(_ mark: Character) {
        switch mark {
        case "-": self = .hold
        case "c": self = .chord(accent: false)
        case "C": self = .chord(accent: true)
        case "u": self = .upperChord
        case "R": self = .bassRoot
        case "5": self = .bassFifth
        case "1", "2", "3", "4": self = .note(Int(String(mark))! - 1)
        default: return nil
        }
    }

    static let marks: Set<Character> = [".", "-", "c", "C", "u", "R", "5", "1", "2", "3", "4"]
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
    let harp: [HarpMark?]
    /// False for a bar without a harp part of its own: the main bar's plays.
    let hasHarp: Bool

    init(_ bar: RhythmBar, steps: Int) {
        hits = (0..<steps).map { bar.hits(at: $0) }
        bass = (0..<steps).map { bar.bassNote(at: $0) }
        hasBass = !bar.bass.isEmpty
        harp = (0..<steps).map { bar.harpMark(at: $0) }
        hasHarp = !bar.harp.isEmpty
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
    // Added 2026-11-23, the styles chord harps and arranger keyboards most often have
    // that the first set lacked.
    case swing, slowRock, march, funk, hipHop, samba, tango

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
        case .swing: return "Swing / Jazz"
        case .slowRock: return "Slow Rock 12/8"
        case .march: return "March"
        case .funk: return "Funk"
        case .hipHop: return "Hip Hop"
        case .samba: return "Samba / Latin"
        case .tango: return "Tango"
        }
    }

    var beatsPerBar: Int { self == .waltz ? 3 : 4 }

    /// Steps in a beat: four sixteenths, or three triplets for the shuffle, swing and
    /// the 12/8 slow rock.
    var stepsPerBeat: Int { [.bluesShuffle, .swing, .slowRock].contains(self) ? 3 : 4 }

    var stepsPerBar: Int { beatsPerBar * stepsPerBeat }

    /// A triplet feel: auto-strum's eighths swing to match (the second on the third
    /// triplet of the beat).
    var swings: Bool { stepsPerBeat == 3 }

    func bar(_ variation: RhythmVariation) -> RhythmBar {
        variation == .a ? patterns.a.with(harp: harp.a) : patterns.b.with(harp: harp.b)
    }

    /// A fill keeps the main bar's harp part.
    var fill: RhythmBar { patterns.fill }
    var intro: RhythmBar { patterns.intro.with(harp: harp.intro) }

    /// The last bar, played when OUTRO is pressed: the next bar line starts it, and
    /// the final hit (crash, kick and the bass's root) lands on the bar after.
    var outro: RhythmBar { outroPattern.with(harp: harp.outro) }

    /// Auto-strum's harp part in the Style pattern, for A, B, the intro and the outro:
    /// what a guitarist or pianist would play in that style.
    private var harp: (a: String, b: String, intro: String, outro: String) {
        switch self {
        case .rock: return ("c-c-c-c-c-c-c-c-", "C--c--c-C--c--c-", "c---------------", "c-c-c-c-c-c-C---")
        case .country: return ("R-..u-..5-..u-..", "R-u-u-u-5-u-u-u-", "c---------------", "R-..u-..5-..C---")
        case .ballad: return ("1-2-3-4-1-2-3-4-", "1---3---4---3---", "1-2-3-4-c-------", "1-2-3-4-C-------")
        case .waltz: return ("R---u---u---", "R---u-u-u-u-", "c-----------", "R---u---C---")
        case .bossa: return ("c-.c-.c-..c-.c-.", "c-.c-..c-.c-.c-.", "c---------------", "c-.c-.c-C-------")
        case .reggae: return ("....u-......u-..", "..u...u...u...u.", "....u-......u-..", "....u-......C---")
        case .bluesShuffle: return ("c-cc-cc-cc-c", "R-u5-uR-u5-u", "c-----------", "c-cc-cC-----")
        case .disco: return ("..c...c...c...c.", "c.c.c.c.c.c.c.c.", "c---------------", "..c...c...C-----")
        case .rnb: return ("c--c--c-....c-..", "..c-..c-..c-.cc-", "c---------------", "c--c--c-C-------")
        case .swing: return ("c-.c-.c-.c-.", "...c-....c-.", "c-----------", "c-.c-.C-----")
        case .slowRock: return ("CuuCuuCuuCuu", "123412341234", "c-----------", "CuuCuuC-----")
        case .march: return ("R---u---5---u---", "R-u-u-u-5-u-u-u-", "................", "R---u---5---C---")
        case .funk: return ("..u...u.u.u...u.", "u.u..u.uu.u..u.u", "u---------------", "..u...u.u.u.C---")
        case .hipHop: return ("c-------....c---", "c---..c-c---..c-", "c---------------", "c-------....C---")
        case .samba: return ("c.c..c.c.c..c.c.", ".cc.c.cc.cc.c.c.", "c---------------", "c.c..c.c.c..C---")
        case .tango: return ("C...c...C...c.c.", "C..cc...C..cc...", "C---------------", "C...c...C---....")
        }
    }

    private var outroPattern: RhythmBar {
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
        case .swing:
            return RhythmBar(drums: [.ride: "x..x.x......", .snare: "......x..xxX", .kick: "x.....x....."],
                             bass: "R--3--5--O--")
        case .slowRock:
            return RhythmBar(drums: [.kick: "x.....x.....", .snare: "...X.....xxX",
                                     .closedHat: "xooxoo......"],
                             bass: "R-----5--R--")
        case .march:
            return RhythmBar(drums: [.kick: "x.......x.......", .snare: "....X...xxxxX..."],
                             bass: "R---5---R---L---")
        case .funk:
            return RhythmBar(drums: [.kick: "x..x..x...x.....", .snare: "....X..o....XxXX",
                                     .closedHat: "xoxoxoxoxoxo...."],
                             bass: "R.RR..5.O.7.R---")
        case .hipHop:
            return RhythmBar(drums: [.kick: "x......x.xx.....", .snare: "....X.......X..."],
                             bass: "R------.R-......")
        case .samba:
            return RhythmBar(drums: [.kick: "x..xx..xx..x....", .rim: "x..x..x...x....."],
                             bass: "R..5R..5R..5R---")
        case .tango:
            return RhythmBar(drums: [.kick: "x...x...x.......", .snare: "............xxX."],
                             bass: "R---5---R---....")
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
        case .swing:
            return (
                RhythmBar(drums: [.ride: "x..x.xx..x.x", .closedHat: "...x.....x..", .kick: "g..g..g..g.."],
                          bass: "R--3--5--6--"),
                RhythmBar(drums: [.ride: "x..x.xx..x.x", .closedHat: "...x.....x..", .snare: ".....o....o."],
                          bass: "R--5--6--5--"),
                RhythmBar(drums: [.kick: "x.....x.....", .snare: "...x..x.xxxX"],
                          bass: ""),
                RhythmBar(drums: [.ride: "x..x.xx..x.x", .closedHat: "...x.....x.."],
                          bass: "R-----------"))
        case .slowRock:
            return (
                RhythmBar(drums: [.kick: "x.....x.x...", .snare: "...X.....X..", .closedHat: "xooxooxooxoo"],
                          bass: "R-----5--R--"),
                RhythmBar(drums: [.kick: "x.....x.....", .snare: "...X.....X..", .ride: "xooxooxooxoo"],
                          bass: "R--3--5--3--"),
                RhythmBar(drums: [.kick: "x.....x.....", .snare: "...X..xxxxxX"],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...........", .closedHat: "xooxooxooxoo"],
                          bass: "R-----------"))
        case .march:
            return (
                RhythmBar(drums: [.kick: "x.......x.......", .snare: "....X.......X.oo", .ride: "x...x...x...x..."],
                          bass: "R-------5-------"),
                RhythmBar(drums: [.kick: "x.......x.......", .snare: "o.o.X.o.o.o.X.oo", .ride: "x...x...x...x..."],
                          bass: "R---5---R---5---"),
                RhythmBar(drums: [.kick: "x.......x.......", .snare: "xoxoxoxoxxxxXXXX"],
                          bass: ""),
                RhythmBar(drums: [.snare: "xoxoxoxoxoxoXxXx"],
                          bass: "................"))
        case .funk:
            return (
                RhythmBar(drums: [.kick: "x..x..x...x.....", .snare: "....X..o.o..X..o", .closedHat: "xoxoxoxoxoxoxoxo"],
                          bass: "R-.R-.5.O-.7.5.."),
                RhythmBar(drums: [.kick: "x.x...x..x......", .snare: "....X......o.oX.", .closedHat: "xoxoxoxoxoxoxoxo"],
                          bass: "R.RR..5.O.7.5.R."),
                RhythmBar(drums: [.kick: "x..x..x.........", .snare: "....X..oxoxoXxXX"],
                          bass: ""),
                RhythmBar(drums: [.kick: "x...............", .closedHat: "xoxoxoxoxoxoxoxo"],
                          bass: "R---------------"))
        case .hipHop:
            return (
                RhythmBar(drums: [.kick: "x......x.xx.....", .snare: "....X.......X...", .closedHat: "x.x.x.x.x.x.x.x."],
                          bass: "R------.R-....5-"),
                RhythmBar(drums: [.kick: "x.x....x..x..x..", .snare: "....X.......X..o", .closedHat: "x.xxx.x.x.xxx.x."],
                          bass: "R-..R--.5-..R---"),
                RhythmBar(drums: [.kick: "x......x.x......", .snare: "....X...x.x.xXxX"],
                          bass: ""),
                RhythmBar(drums: [.closedHat: "x.x.x.x.x.x.x.x.", .snare: "............X..."],
                          bass: "................"))
        case .samba:
            return (
                RhythmBar(drums: [.kick: "x..xx..xx..xx..x", .rim: "x..x..x...x..x..", .tambourine: "xooxxooxxooxxoox"],
                          bass: "R..5R..5R..5R..5"),
                RhythmBar(drums: [.kick: "x..xx..xx..xx..x", .rim: "..x..x...x..x...", .tambourine: "xooxxooxxooxxoox",
                                  .lowConga: "......x.......x."],
                          bass: "R..5O..5R..5O..5"),
                RhythmBar(drums: [.kick: "x..xx..xx..x....", .snare: "....x.x.xxxxXxXx"],
                          bass: ""),
                RhythmBar(drums: [.tambourine: "xooxxooxxooxxoox"],
                          bass: "R---------------"))
        case .tango:
            return (
                RhythmBar(drums: [.kick: "x...x...x...x...", .snare: "..............x.", .rim: "x..x..x.x......."],
                          bass: "R---5---R---5-5-"),
                RhythmBar(drums: [.kick: "x..xx...x..xx...", .rim: "x..x..x.x..x..x."],
                          bass: "R--5R...R--5R..."),
                RhythmBar(drums: [.kick: "x...x...x.......", .snare: "x.x.x.x.xxxxXXXX"],
                          bass: ""),
                RhythmBar(drums: [.rim: "x..x..x.x......."],
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
