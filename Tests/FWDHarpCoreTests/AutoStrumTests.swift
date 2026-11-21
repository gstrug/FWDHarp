import XCTest
@testable import FWDHarpCore

/// Auto-strum's patterns and tap tempo.
final class AutoStrumTests: XCTestCase {
    private let c = MajorKey(tonic: 0)
    private var plate: [Int] { StrumPlate.notes(for: c.chord(degree: 1), strings: 10, from: 48) }

    private func run(_ pattern: AutoStrumPattern, steps: Int, chord: Chord? = nil) -> [[Int]] {
        let chord = chord ?? c.chord(degree: 1)
        let notes = StrumPlate.notes(for: chord, strings: 10, from: 48)
        return (0..<steps).map { AutoStrum.notes(pattern, step: $0, plateNotes: notes, chord: chord) }
    }

    func testArpeggioUpRepeatsTheChordWithTheRootOnTop() {
        XCTAssertEqual(run(.arpeggioUp, steps: 5), [[48], [52], [55], [60], [48]], "C E G C, C …")
    }

    func testArpeggioUpDownDoesNotRepeatTheEnds() {
        XCTAssertEqual(run(.arpeggioUpDown, steps: 7).flatMap { $0 }, [48, 52, 55, 60, 55, 52, 48])
    }

    func testTheSeventhJoinsTheFigure() {
        XCTAssertEqual(run(.arpeggioUp, steps: 5, chord: c.chord(degree: 1).withSeventh).flatMap { $0 },
                       [48, 52, 55, 58, 60], "C E G B♭ C")
    }

    func testBlockChordsPlayTheFigureTogether() {
        XCTAssertEqual(run(.blockChords, steps: 2), [[48, 52, 55, 60], [48, 52, 55, 60]])
    }

    func testBassAndChordIsOomPah() {
        let steps = run(.bassAndChord, steps: 4)
        XCTAssertEqual(steps[0], [36], "the root an octave below")
        XCTAssertEqual(steps[1], [48, 52, 55])
        XCTAssertEqual(steps[2], [43], "then the 5th")
        XCTAssertEqual(steps[3], [48, 52, 55])
    }

    func testBassFollowsTheChordNotTheKey() {
        let g = c.chord(degree: 5)
        let steps = run(.bassAndChord, steps: 3, chord: g)
        XCTAssertEqual(steps[0], [43], "G2 under the plate's lowest G")
        XCTAssertEqual(steps[2], [50])
    }

    func testStepTimes() {
        XCTAssertEqual(AutoStrum.stepInterval(.arpeggioUp, tempo: 120), 0.25, accuracy: 1e-9, "eighths")
        XCTAssertEqual(AutoStrum.stepInterval(.blockChords, tempo: 120), 0.5, accuracy: 1e-9)
        XCTAssertEqual(AutoStrum.stepInterval(.singleSweep, tempo: 120), 0)
        XCTAssertEqual(AutoStrum.stepInterval(.blockChords, tempo: 1000), 0.25, accuracy: 1e-9, "held to 240")
    }

    func testTapTempo() {
        var tapper = TapTempo()
        XCTAssertNil(tapper.tap(at: 10))
        XCTAssertEqual(tapper.tap(at: 10.5), 120)
        XCTAssertEqual(tapper.tap(at: 11.0), 120)
        XCTAssertNil(tapper.tap(at: 20), "a long pause starts afresh")
        XCTAssertEqual(tapper.tap(at: 21), 60)
        var quick = TapTempo()
        _ = quick.tap(at: 0)
        XCTAssertEqual(quick.tap(at: 0.1), 240, "held to the fastest tempo")
    }

    func testPatternAndTempoAreSaved() throws {
        var setup = HarpSetup()
        setup.autoStrumPattern = .bassAndChord
        setup.tempo = 132
        let back = try SetupStorage.decode(JSONEncoder().encode(setup))
        XCTAssertEqual(back.autoStrumPattern, .bassAndChord)
        XCTAssertEqual(back.tempo, 132)
        let later = try SetupStorage.decode(Data(#"{"autoStrumPattern": "somethingNew", "tempo": 9999}"#.utf8))
        XCTAssertEqual(later.autoStrumPattern, .arpeggioUp)
        XCTAssertEqual(later.tempo, AutoStrum.defaultTempo)
    }
}
