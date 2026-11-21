import XCTest
import CoreGraphics
@testable import FWDHarpCore

/// The pads, the 7 modifier and the strum plate.
final class PadTests: XCTestCase {
    private let c = MajorKey(tonic: 0)

    func testThePadsPlayTheSixChordsOfTheKey() {
        var names: [String] = []
        for pad in ChordPad.allCases where !pad.isModifier {
            var selection = PadSelection()
            selection.press(pad)
            names.append(selection.chord(in: c)!.name(preferFlats: false))
        }
        XCTAssertEqual(names, ["F", "C", "G", "Dm", "Am", "Em"], "4 1 5 on top, 2 6 3 below")
    }

    func testSusReplacesTheThird() {
        var selection = PadSelection()
        selection.press(.one)
        selection.press(.sus4)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "Csus4")
        XCTAssertEqual(selection.chord(in: c)?.pitchClasses, [0, 5, 7], "C F G")
        selection.release(.sus4)
        selection.press(.sus2)
        XCTAssertEqual(selection.chord(in: c)?.pitchClasses, [0, 2, 7], "C D G")
        selection.release(.one)
        selection.press(.six)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "Asus2",
                       "a minor chord suspends like a major one")
    }

    func testTheSeventhWithASusGivesSevenSus() {
        var selection = PadSelection()
        selection.press(.five)
        selection.press(.seven)
        selection.press(.sus4)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "G7sus4")
        XCTAssertEqual(selection.chord(in: c)?.pitchClasses, [7, 0, 2, 5], "G C D F")
    }

    func testWithBothSusPadsTheLastPressedCounts() {
        var selection = PadSelection()
        selection.press(.one)
        selection.press(.sus2)
        selection.press(.sus4)
        XCTAssertEqual(selection.suspension, .fourth)
        selection.release(.sus4)
        XCTAssertEqual(selection.suspension, .second, "the other is still held")
        XCTAssertTrue(selection.isHeld(.sus2))
        XCTAssertFalse(selection.isHeld(.sus4))
    }

    func testTheSevenAddsTheCommonSeventh() {
        var selection = PadSelection()
        selection.press(.seven)
        selection.press(.one)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "C7")
        XCTAssertEqual(selection.chord(in: c)?.pitchClasses, [0, 4, 7, 10], "C E G B♭")
        selection.release(.one)
        selection.press(.six)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "Am7")
        selection.release(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "Am")
    }

    func testTheSevenAloneIsNoChord() {
        var selection = PadSelection()
        selection.press(.seven)
        XCTAssertNil(selection.chord(in: c))
    }

    func testTheLastPadPressedWinsAndHandsBack() {
        var selection = PadSelection()
        selection.press(.one)
        selection.press(.five)
        XCTAssertEqual(selection.current, .five)
        selection.release(.five)
        XCTAssertEqual(selection.current, .one, "the pad still held takes over")
        selection.release(.one)
        XCTAssertNil(selection.current)
    }

    func testFlatKeysNameTheirSevenths() {
        var selection = PadSelection()
        selection.press(.seven)
        selection.press(.five)
        let f = MajorKey(tonic: 5)
        XCTAssertEqual(selection.chord(in: f)?.name(preferFlats: f.prefersFlats), "C7")
        selection.release(.five)
        selection.press(.four)
        XCTAssertEqual(selection.chord(in: f)?.name(preferFlats: f.prefersFlats), "B♭7")
    }

    func testHoldKeepsTheLastChordAfterLifting() {
        var selection = PadSelection()
        selection.setHolding(true)
        selection.press(.five)
        selection.release(.five)
        XCTAssertEqual(selection.current, .five, "kept after lifting")
        selection.press(.seven)
        XCTAssertEqual(selection.chord(in: c)?.name(preferFlats: false), "G7", "modifiers still work on it")
        selection.release(.seven)
        selection.press(.two)
        selection.release(.two)
        XCTAssertEqual(selection.current, .two, "a new pad replaces it")
        selection.setHolding(false)
        XCTAssertNil(selection.current, "Hold off: the kept chord goes")
    }

    func testWithoutHoldLiftingLeavesNoChord() {
        var selection = PadSelection()
        selection.press(.one)
        selection.release(.one)
        XCTAssertNil(selection.current)
    }

    func testPadsDoNotOverlapAndATouchFindsItsPad() {
        let layout = PadLayout(size: CGSize(width: 700, height: 500))
        let frames = ChordPad.allCases.map(layout.frame(of:))
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].intersects(frames[j]),
                               "\(ChordPad.allCases[i]) and \(ChordPad.allCases[j]) overlap")
            }
            let centre = CGPoint(x: frames[i].midX, y: frames[i].midY)
            XCTAssertEqual(layout.pad(at: centre), ChordPad.allCases[i])
        }
        XCTAssertNil(layout.pad(at: CGPoint(x: -5, y: -5)))
    }

    func testThePadsFitTheSpaceGiven() {
        let size = CGSize(width: 640, height: 420)
        let layout = PadLayout(size: size)
        for pad in ChordPad.allCases {
            let frame = layout.frame(of: pad)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertGreaterThanOrEqual(frame.minY, 0)
            XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.001)
            XCTAssertLessThanOrEqual(frame.maxY, size.height + 0.001)
        }
    }
}

final class StrumPlateTests: XCTestCase {
    func testThreeOctavesOfAChordRootToRoot() {
        let strings = StrumPlate.stringCount(octaves: 3)
        XCTAssertEqual(strings, 10)
        let c = MajorKey(tonic: 0)
        let notes = StrumPlate.notes(for: c.chord(degree: 1), strings: strings,
                                     from: StrumPlate.lowestNote(in: c))
        XCTAssertEqual(notes, [48, 52, 55, 60, 64, 67, 72, 76, 79, 84], "C3 up to C6")
    }

    func testOtherChordsStartFromTheirFirstNoteAboveTheBottom() {
        let c = MajorKey(tonic: 0)
        let g = StrumPlate.notes(for: c.chord(degree: 5), strings: 4, from: 48)
        XCTAssertEqual(g, [50, 55, 59, 62], "D G B D: the plate stays in place")
    }

    func testTheSeventhAddsNotesOnTheSameStrings() {
        let c = MajorKey(tonic: 0)
        let notes = StrumPlate.notes(for: c.chord(degree: 1).withSeventh, strings: 10, from: 48)
        XCTAssertEqual(notes.count, 10)
        XCTAssertEqual(Array(notes.prefix(5)), [48, 52, 55, 58, 60], "B♭ joins in")
    }

    func testThePlateFollowsTheKey() {
        XCTAssertEqual(StrumPlate.lowestNote(in: MajorKey(tonic: 7)), 55, "G3 in G")
    }

    func testStringsByHeight() {
        XCTAssertEqual(StrumPlate.string(atHeight: 0, strings: 10), 0, "bottom")
        XCTAssertEqual(StrumPlate.string(atHeight: 1, strings: 10), 9, "top")
        XCTAssertEqual(StrumPlate.string(atHeight: 0.55, strings: 10), 5)
        XCTAssertEqual(StrumPlate.string(atHeight: -1, strings: 10), 0)
    }

    func testLouderToTheRight() {
        XCTAssertEqual(StrumPlate.velocity(atWidth: 0), 30)
        XCTAssertEqual(StrumPlate.velocity(atWidth: 1), 127)
        XCTAssertLessThan(StrumPlate.velocity(atWidth: 0.3), StrumPlate.velocity(atWidth: 0.7))
        XCTAssertEqual(StrumPlate.velocity(atWidth: 5), 127)
    }

    func testAFastStrumPlaysEveryStringItCrossed() {
        XCTAssertEqual(StrumPlate.strings(crossedFrom: 2, to: 5), [3, 4, 5])
        XCTAssertEqual(StrumPlate.strings(crossedFrom: 5, to: 2), [4, 3, 2], "downward, in order")
        XCTAssertEqual(StrumPlate.strings(crossedFrom: 3, to: 3), [])
    }

    func testWiderRangesAddStrings() {
        XCTAssertEqual(StrumPlate.octaveRange.map(StrumPlate.stringCount(octaves:)), [10, 13, 16])
    }

    func testTheOctaveButtonsMoveThePlate() {
        let c = MajorKey(tonic: 0)
        XCTAssertEqual(StrumPlate.lowestNote(in: c, octaveShift: -1), 36, "C2")
        XCTAssertEqual(StrumPlate.lowestNote(in: c, octaveShift: 2), 72, "C5")
        let high = StrumPlate.notes(for: c.chord(degree: 1), strings: 16,
                                    from: StrumPlate.lowestNote(in: MajorKey(tonic: 11), octaveShift: 2))
        XCTAssertTrue(high.allSatisfy { $0 <= 127 }, "never past the top of MIDI")
    }

    func testRangeAndOctaveAreSavedAndKeptInBounds() throws {
        var setup = HarpSetup()
        setup.plateOctaves = 5
        setup.octaveShift = -1
        let back = try SetupStorage.decode(JSONEncoder().encode(setup))
        XCTAssertEqual(back.plateOctaves, 5)
        XCTAssertEqual(back.octaveShift, -1)
        let bad = try SetupStorage.decode(Data(#"{"plateOctaves": 9, "octaveShift": 7}"#.utf8))
        XCTAssertEqual(bad.plateOctaves, 3)
        XCTAssertEqual(bad.octaveShift, 0)
        let old = try SetupStorage.decode(Data("{}".utf8))
        XCTAssertEqual(old.plateOctaves, 3, "a file from before keeps today's spread")
    }

    func testTheKeyIsSaved() throws {
        var setup = HarpSetup()
        setup.keyTonic = 7
        let data = try JSONEncoder().encode(setup)
        XCTAssertEqual(try SetupStorage.decode(data).key, MajorKey(tonic: 7))
        let bad = Data(#"{"keyTonic": 40}"#.utf8)
        XCTAssertEqual(try SetupStorage.decode(bad).keyTonic, 0)
    }
}
