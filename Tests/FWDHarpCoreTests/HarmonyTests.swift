import XCTest
@testable import FWDHarpCore

final class HarmonyTests: XCTestCase {
    func testTheChordsOfCMajor() {
        let key = MajorKey(tonic: 0)
        let names = (1...7).map { key.chord(degree: $0).name(preferFlats: key.prefersFlats) }
        XCTAssertEqual(names, ["C", "Dm", "Em", "F", "G", "Am", "Bdim"])
    }

    func testFlatKeysNameTheirChordsWithFlats() {
        let key = MajorKey(tonic: 5)   // F
        XCTAssertEqual(key.name, "F")
        XCTAssertEqual(key.chord(degree: 4).name(preferFlats: key.prefersFlats), "B♭")
    }

    func testAChordsNotes() {
        XCTAssertEqual(MajorKey(tonic: 7).chord(degree: 5).pitchClasses, [2, 6, 9], "D major in G")
        XCTAssertEqual(MajorKey(tonic: 0).chord(degree: 7).pitchClasses, [11, 2, 5], "B diminished")
    }
}
