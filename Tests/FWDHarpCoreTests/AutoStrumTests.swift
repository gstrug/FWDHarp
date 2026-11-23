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

    /// Steps per beat: the conductor's grid (eighths, or a chord a beat).
    func testStepsPerBeat() {
        XCTAssertEqual(AutoStrumPattern.arpeggioUp.stepsPerBeat, 2, "eighths")
        XCTAssertEqual(AutoStrumPattern.blockChords.stepsPerBeat, 1)
        XCTAssertFalse(AutoStrumPattern.singleSweep.isRhythmic)
    }

    /// The cycle worked out once is the same as asking step by step.
    func testCycleMatchesSteps() {
        let g = c.chord(degree: 5)
        let plate = StrumPlate.notes(for: g, strings: 10, from: StrumPlate.lowestNote(in: c, octaveShift: 0))
        for pattern in AutoStrumPattern.allCases where pattern.isRhythmic {
            for scale in [nil, PlateScale.blues.autoStrumColour(in: c, chord: g)] {
                let cycle = AutoStrum.cycle(pattern, plateNotes: plate, chord: g, scale: scale)
                XCTAssertFalse(cycle.isEmpty, "\(pattern)")
                for step in 0..<20 {
                    XCTAssertEqual(cycle[step % cycle.count],
                                   AutoStrum.notes(pattern, step: step, plateNotes: plate, chord: g, scale: scale))
                }
            }
        }
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

/// Scales on the plate, and tapping a kept modifier off.
final class ScaleTests: XCTestCase {
    private let c = MajorKey(tonic: 0)

    private func names(_ notes: [Int]) -> [String] {
        notes.map { NoteNames.name($0 % 12, preferFlats: true) }
    }

    private func plate(_ scale: PlateScale, key: MajorKey? = nil, chord: Chord? = nil, strings: Int = 10,
                       shift: Int = 0, pattern: PlatePattern = .straight) -> [Int] {
        StrumPlate.notes(for: scale, in: key ?? c, chord: chord, strings: strings, octaveShift: shift,
                         pattern: pattern)
    }

    func testEveryScaleHasTheStringsChosen() {
        for scale in PlateScale.allCases where scale != .chord {
            XCTAssertEqual(plate(scale, strings: 13).count, 13, scale.title)
        }
        XCTAssertEqual(plate(.chromatic, strings: 13), Array(48...60), "one octave, never crowded")
    }

    func testTheKeysScales() {
        XCTAssertEqual(names(plate(.major, strings: 8)), ["C", "D", "E", "F", "G", "A", "B", "C"])
        XCTAssertEqual(Set(names(plate(.naturalMinor, strings: 7))), ["A", "B", "C", "D", "E", "F", "G"],
                       "A minor's notes: the key's relative minor")
        XCTAssertEqual(names(plate(.chromatic, strings: 3)), ["C", "D♭", "D"])
    }

    func testPentatonicAndBluesFollowTheChord() {
        XCTAssertEqual(names(plate(.pentatonic, strings: 5)), ["C", "D", "E", "G", "A"], "no chord: the key's")
        let g = c.chord(degree: 5)
        XCTAssertEqual(Set(names(plate(.pentatonic, chord: g, strings: 5))), ["G", "A", "B", "D", "E"],
                       "over G: G major pentatonic")
        let am = c.chord(degree: 6)
        XCTAssertEqual(Set(names(plate(.pentatonic, chord: am, strings: 5))), ["A", "C", "D", "E", "G"],
                       "over Am: A minor pentatonic")
        XCTAssertEqual(Set(names(plate(.blues, chord: c.chord(degree: 1), strings: 6))),
                       ["C", "D", "E♭", "E", "G", "A"], "over C: C major blues")
        XCTAssertEqual(Set(names(plate(.blues, chord: c.chord(degree: 4), strings: 6))),
                       ["F", "G", "A♭", "A", "C", "D"], "over F: F major blues, which fits F")
        XCTAssertEqual(Set(names(plate(.blues, chord: am, strings: 6))),
                       ["A", "C", "D", "E♭", "E", "G"], "over Am: A minor blues")
        XCTAssertEqual(Set(names(plate(.blues, chord: am.withSeventh, strings: 6))),
                       ["A", "C", "D", "E♭", "E", "G"], "Am7 is minor too")
        XCTAssertTrue(PlateScale.isMinorFlavour(c.chord(degree: 1).suspended(.fourth)), "sus4 takes the minor form")
        XCTAssertFalse(PlateScale.isMinorFlavour(c.chord(degree: 1).suspended(.second)))
    }

    func testTheMajorScaleStaysInTheKeyOverAnyChord() {
        XCTAssertEqual(plate(.major, chord: c.chord(degree: 5)), plate(.major), "no F♯ over G in C")
    }

    func testScalesStartAtThePlatesBottomAndFollowTheOctave() {
        let g = plate(.pentatonic, key: MajorKey(tonic: 7), shift: -1)
        XCTAssertEqual(g.first, 43, "G2")
        XCTAssertEqual(plate(.blues, chord: c.chord(degree: 5)).first, 50,
                       "the scale's first note from the plate's bottom (C3), whatever the chord: D3 over G")
    }

    func testPlateOrdersWorkOnScales() {
        XCTAssertEqual(Array(plate(.major, pattern: .alternating).prefix(4)), [48, 52, 50, 53], "C E D F: in thirds")
        XCTAssertEqual(plate(.major, pattern: .bassAndChord), plate(.major), "no chord to take a bass from, so straight")
    }

    func testChordMeansNoScale() {
        XCTAssertEqual(plate(.chord), [])
    }

    func testArpeggiosTakeTheScalesColour() {
        let plain = [48, 52, 55, 60]                         // C E G C
        let blues = PlateScale.blues.pitchClasses(in: c, chord: c.chord(degree: 1))!
        XCTAssertEqual(AutoStrum.colouredFigure(plain, scale: blues), [48, 51, 52, 55, 57, 60],
                       "C E♭ E G A C: the blue note slides into E")
        let major = PlateScale.major.pitchClasses(in: c, chord: nil)!
        XCTAssertEqual(AutoStrum.colouredFigure(plain, scale: major), [48, 50, 52, 53, 55, 59, 60],
                       "at most one passing note between chord notes")
        let notes = StrumPlate.notes(for: c.chord(degree: 1), strings: 10, from: 48)
        let up = (0..<6).flatMap { AutoStrum.notes(.arpeggioUp, step: $0, plateNotes: notes,
                                                   chord: c.chord(degree: 1), scale: blues) }
        XCTAssertEqual(up, [48, 51, 52, 55, 57, 60])
        XCTAssertEqual(AutoStrum.notes(.blockChords, step: 0, plateNotes: notes, chord: c.chord(degree: 1),
                                       scale: blues), [48, 52, 55, 60], "chord patterns stay chords")
    }

    func testTheScaleIsSaved() throws {
        var setup = HarpSetup()
        setup.plateScale = .blues
        XCTAssertEqual(try SetupStorage.decode(JSONEncoder().encode(setup)).plateScale, .blues)
        XCTAssertEqual(try SetupStorage.decode(Data("{}".utf8)).plateScale, .chord)
    }

    func testASecondTapTakesAKeptModifierOff() {
        var selection = PadSelection()
        selection.setHolding(true)
        selection.press(.one)
        selection.release(.one)
        selection.press(.seven)
        selection.release(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C7")
        selection.press(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C", "off at once, finger still down")
        selection.release(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C")
        selection.press(.sus2)
        selection.release(.sus2)
        selection.press(.sus4)
        selection.release(.sus4)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "Csus4", "the other sus swaps in")
        selection.press(.sus4)
        selection.release(.sus4)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C")
    }

    func testWithoutHoldModifiersAreOnlyWhileHeld() {
        var selection = PadSelection()
        selection.press(.one)
        selection.press(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C7")
        selection.release(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C")
        selection.press(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C7", "a second press is still on")
    }
}

final class StopKeptChordTests: XCTestCase {
    func testStopLetsTheKeptChordGoButLeavesHoldOn() {
        var selection = PadSelection()
        selection.setHolding(true)
        selection.press(.seven)
        selection.press(.one)
        selection.release(.one)
        selection.release(.seven)
        XCTAssertEqual(selection.current, .one)
        selection.releaseKept()
        XCTAssertNil(selection.current)
        XCTAssertFalse(selection.isInForce(.seven))
        XCTAssertTrue(selection.isHolding)
        selection.press(.five)
        selection.release(.five)
        XCTAssertEqual(selection.current, .five, "Hold keeps the next chord")
    }
}
