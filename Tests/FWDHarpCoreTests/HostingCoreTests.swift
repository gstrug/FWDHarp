import XCTest
@testable import FWDHarpCore

/// The pure parts of the hosting copied from FWD Sequencer.
final class HostingCoreTests: XCTestCase {
    func testAnOldLoadCannotFinishANewerOne() {
        var tracker = PluginLoadTracker()
        let part = UUID()
        let first = tracker.begin(for: part)
        let second = tracker.begin(for: part)
        XCTAssertFalse(tracker.finish(for: part, token: first), "a superseded load must be turned away")
        XCTAssertFalse(tracker.isEmpty)
        XCTAssertTrue(tracker.finish(for: part, token: second))
        XCTAssertTrue(tracker.isEmpty)
    }

    func testPluginsAreTheSameByComponentNotByID() {
        let a = PluginInfo(name: "Synth", manufacturerName: "Maker",
                           componentType: 1, componentSubType: 2, componentManufacturer: 3)
        var b = a
        b.id = UUID()
        b.name = "Synth (renamed)"
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.componentIdentifier, "1-2-3")
    }

    func testGeneralMIDINames() {
        XCTAssertEqual(GeneralMIDI.names.count, 128)
        XCTAssertEqual(GeneralMIDI.families.count, 16)
        XCTAssertEqual(GeneralMIDI.name(of: 46), "Orchestral Harp", "the default sound")
        XCTAssertEqual(GeneralMIDI.soundName(GeneralMIDI.drumKit), "Drum Kit")
    }
}
