import XCTest
@testable import FWDHarpCore

final class HarmonyTests: XCTestCase {
    func testTheChordsOfCMajor() {
        let key = MusicKey(tonic: 0)
        let names = (1...7).map { key.chord(degree: $0).name(preferFlats: key.prefersFlats) }
        XCTAssertEqual(names, ["C", "Dm", "Em", "F", "G", "Am", "Bdim"])
    }

    func testFlatKeysNameTheirChordsWithFlats() {
        let key = MusicKey(tonic: 5)   // F
        XCTAssertEqual(key.name, "F")
        XCTAssertEqual(key.chord(degree: 4).name(preferFlats: key.prefersFlats), "B♭")
    }

    func testAChordsNotes() {
        XCTAssertEqual(MusicKey(tonic: 7).chord(degree: 5).pitchClasses, [2, 6, 9], "D major in G")
        XCTAssertEqual(MusicKey(tonic: 0).chord(degree: 7).pitchClasses, [11, 2, 5], "B diminished")
    }

    /// Minor keys (Graham, 2026-11-23): the key's own chords on top, iv i V, the 5
    /// major as song books play it; their relatives underneath, VI III VII.
    func testMinorKeyPads() {
        let aMinor = MusicKey(tonic: 9, minor: true)
        let pads: [ChordPad] = [.four, .one, .five, .two, .six, .three]
        XCTAssertEqual(pads.map { $0.chord(in: aMinor)!.name(preferFlats: aMinor.prefersFlats) },
                       ["Dm", "Am", "E", "F", "C", "G"])
        XCTAssertEqual(pads.map { $0.degreeLabel(in: aMinor) }, ["iv", "i", "V", "VI", "III", "VII"])
        XCTAssertEqual(pads.map { $0.chord(in: MusicKey(tonic: 0))!.name(preferFlats: false) },
                       ["F", "C", "G", "Dm", "Am", "Em"], "major keys as before")
        XCTAssertEqual(aMinor.name, "Am")
        XCTAssertEqual(aMinor.fullName, "A minor")
        XCTAssertEqual(aMinor.scale, [9, 11, 0, 2, 4, 5, 7])
        XCTAssertTrue(MusicKey(tonic: 2, minor: true).prefersFlats, "D minor has F major's flat")
        XCTAssertEqual(MusicKey(tonic: 2, minor: true).chord(degree: 6).name(preferFlats: true), "B♭")
        XCTAssertEqual(MusicKey.all.count, 24)
        XCTAssertEqual(Set(MusicKey.all).count, 24)
        // The 7th on the minor key's major 5 is the dominant 7th that leads home.
        XCTAssertEqual(ChordPad.five.chord(in: aMinor)!.withSeventh.name(preferFlats: false), "E7")
    }

    func testTheMinorKeyIsSaved() throws {
        var setup = HarpSetup()
        setup.keyTonic = 4
        setup.keyMinor = true
        let back = try SetupStorage.decode(JSONEncoder().encode(setup))
        XCTAssertEqual(back.key, MusicKey(tonic: 4, minor: true))
        XCTAssertFalse(try SetupStorage.decode(Data(#"{"keyTonic": 7}"#.utf8)).key.isMinor,
                       "a setup from before minor keys opens in its major key")
    }
}
