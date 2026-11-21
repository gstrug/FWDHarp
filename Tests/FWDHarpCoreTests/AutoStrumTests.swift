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

/// More arpeggios, plate note orders, and Hold keeping the modifiers.
final class PatternOptionTests: XCTestCase {
    private let c = MajorKey(tonic: 0)
    private var cMajor: Chord { c.chord(degree: 1) }

    private func plate(_ pattern: PlatePattern, strings: Int = 10) -> [Int] {
        StrumPlate.notes(for: cMajor, strings: strings, from: 48, pattern: pattern)
    }

    func testTwoOctaveArpeggios() {
        let notes = StrumPlate.notes(for: cMajor, strings: 10, from: 48)
        let up = (0..<8).flatMap { AutoStrum.notes(.arpeggio2Up, step: $0, plateNotes: notes, chord: cMajor) }
        XCTAssertEqual(up, [48, 52, 55, 60, 64, 67, 72, 48], "C to C two octaves up, then again")
        let down = (0..<7).flatMap { AutoStrum.notes(.arpeggio2Down, step: $0, plateNotes: notes, chord: cMajor) }
        XCTAssertEqual(down, [72, 67, 64, 60, 55, 52, 48])
        let upDown = (0..<13).flatMap { AutoStrum.notes(.arpeggio2UpDown, step: $0, plateNotes: notes, chord: cMajor) }
        XCTAssertEqual(upDown, [48, 52, 55, 60, 64, 67, 72, 67, 64, 60, 55, 52, 48])
        let oneDown = (0..<4).flatMap { AutoStrum.notes(.arpeggioDown, step: $0, plateNotes: notes, chord: cMajor) }
        XCTAssertEqual(oneDown, [60, 55, 52, 48])
    }

    func testStraightIsUnchanged() {
        XCTAssertEqual(plate(.straight), StrumPlate.notes(for: cMajor, strings: 10, from: 48))
    }

    func testAlternating() {
        XCTAssertEqual(plate(.alternating), [48, 55, 52, 60, 55, 64, 60, 67, 64, 72], "C G E C' G E' …")
    }

    func testRolling() {
        XCTAssertEqual(plate(.rolling), [48, 52, 55, 52, 55, 60, 55, 60, 64, 60], "two up, one back")
    }

    func testOctaves() {
        XCTAssertEqual(plate(.octaves), [48, 60, 52, 64, 55, 67, 60, 72, 64, 76])
    }

    func testBassAndChord() {
        XCTAssertEqual(plate(.bassAndChord), [36, 43, 36, 43, 48, 52, 55, 60, 64, 67],
                       "root and 5th below on the bottom strings, the chord above")
        XCTAssertEqual(plate(.bassAndChord, strings: 16).prefix(6), [36, 43, 36, 43, 36, 43])
    }

    func testEveryOrderFillsEveryStringAndStaysInMIDI() {
        for pattern in PlatePattern.allCases {
            XCTAssertEqual(plate(pattern, strings: 16).count, 16, pattern.title)
            let high = StrumPlate.notes(for: cMajor, strings: 16, from: 96, pattern: pattern)
            XCTAssertTrue(high.allSatisfy { (0...127).contains($0) }, pattern.title)
        }
    }

    func testThePlateOrderIsSaved() throws {
        var setup = HarpSetup()
        setup.platePattern = .rolling
        XCTAssertEqual(try SetupStorage.decode(JSONEncoder().encode(setup)).platePattern, .rolling)
        XCTAssertEqual(try SetupStorage.decode(Data(#"{"platePattern": "new"}"#.utf8)).platePattern, .straight)
    }

    func testHoldKeepsTheModifiersTheChordWasPlayedWith() {
        var selection = PadSelection()
        selection.setHolding(true)
        selection.press(.seven)
        selection.press(.five)
        selection.release(.five)
        selection.release(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "G7", "the 7th is kept too")
        XCTAssertTrue(selection.isInForce(.seven))
        XCTAssertFalse(selection.isHeld(.seven))
    }

    func testAModifierAddedToTheKeptChordStays() {
        var selection = PadSelection()
        selection.setHolding(true)
        selection.press(.one)
        selection.release(.one)
        selection.press(.sus4)
        selection.release(.sus4)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "Csus4")
        selection.press(.one)
        selection.release(.one)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C", "pressed again, plain")
    }

    func testOtherPadsShowOnlyTheModifiersHeld() {
        var selection = PadSelection()
        selection.setHolding(true)
        selection.press(.seven)
        selection.press(.one)
        selection.release(.one)
        selection.release(.seven)
        XCTAssertEqual(selection.chord(on: .four, in: c)?.name(preferFlats: false), "F",
                       "pressing F now would play plain F")
    }

    func testHoldOffDropsTheKeptModifiers() {
        var selection = PadSelection()
        selection.setHolding(true)
        selection.press(.seven)
        selection.press(.one)
        selection.release(.one)
        selection.release(.seven)
        selection.setHolding(false)
        XCTAssertFalse(selection.isInForce(.seven))
        XCTAssertNil(selection.current)
    }

    func testTurningHoldOnNeverBringsBackAnOldChord() {
        var selection = PadSelection()
        selection.press(.one)
        selection.release(.one)
        selection.setHolding(true)
        XCTAssertNil(selection.current)
    }
}
