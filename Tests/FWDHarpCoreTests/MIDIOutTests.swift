import XCTest
@testable import FWDHarpCore

/// MIDI out's settings and the bytes it sends.
final class MIDIOutTests: XCTestCase {
    func testOffUntilAskedAndOwnSoundOn() throws {
        let settings = try SetupStorage.decode(Data("{}".utf8)).midiOut
        XCTAssertFalse(settings.enabled)
        XCTAssertTrue(settings.playsOwnSound(.plate))
        XCTAssertTrue(settings.playsOwnSound(.auto))
        XCTAssertEqual(settings.channel(for: .plate), 1)
        XCTAssertEqual(settings.channel(for: .auto), 2)
    }

    func testSettingsAreSavedAndKeptInRange() throws {
        var setup = HarpSetup()
        setup.midiOut.enabled = true
        setup.midiOut.setPlaysOwnSound(false, for: .auto)
        setup.midiOut.setChannel(5, for: .auto)
        setup.midiOut.destinations = [42, 42, 7]
        let back = try SetupStorage.decode(JSONEncoder().encode(setup)).midiOut
        XCTAssertTrue(back.enabled)
        XCTAssertTrue(back.playsOwnSound(.plate))
        XCTAssertFalse(back.playsOwnSound(.auto), "each part's own")
        XCTAssertEqual(back.autoChannel, 5)
        XCTAssertEqual(back.destinations, [42, 7], "each destination once")
        let bad = try SetupStorage.decode(Data(#"{"midiOut": {"plateChannel": 40, "autoChannel": 0}}"#.utf8)).midiOut
        XCTAssertEqual(bad.plateChannel, 16)
        XCTAssertEqual(bad.autoChannel, 1)
    }

    func testBytes() {
        XCTAssertEqual(MIDIBytes.noteOn(60, velocity: 100, channel: 1), [0x90, 60, 100])
        XCTAssertEqual(MIDIBytes.noteOn(60, velocity: 100, channel: 2), [0x91, 60, 100])
        XCTAssertEqual(MIDIBytes.noteOff(60, channel: 10), [0x89, 60, 0])
        XCTAssertEqual(MIDIBytes.noteOn(60, velocity: 0, channel: 1)[2], 1,
                       "a note-on is never velocity 0, which would mean note-off")
        XCTAssertEqual(MIDIBytes.panic(channel: 16), [0xBF, 64, 0, 0xBF, 123, 0])
    }

    func testTheOldSingleSwitchCoversBothParts() throws {
        let old = try SetupStorage.decode(Data(#"{"midiOut": {"internalSound": false}}"#.utf8)).midiOut
        XCTAssertFalse(old.playsOwnSound(.plate))
        XCTAssertFalse(old.playsOwnSound(.auto))
    }
}
