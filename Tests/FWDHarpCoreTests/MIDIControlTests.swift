import XCTest
@testable import FWDHarpCore

/// MIDI Learn's links and templates, and following an incoming MIDI clock.
final class MIDIControlTests: XCTestCase {
    private let cc7 = MIDIControlSource(kind: .controlChange, channel: 1, number: 7)
    private let noteC3 = MIDIControlSource(kind: .note, channel: 10, number: 48)

    func testLearnReplacesBothSides() {
        var template = MIDIControllerTemplate(name: "Mine")
        template.learn(cc7, for: .partVolume(.plate))
        template.learn(cc7, for: .masterVolume)
        XCTAssertEqual(template.mappings.count, 1, "one control per message")
        XCTAssertEqual(template.mapping(for: .masterVolume)?.source, cc7)
        template.learn(noteC3, for: .masterVolume)
        XCTAssertEqual(template.mappings.count, 1, "one message per control")
        XCTAssertEqual(template.mapping(for: .masterVolume)?.source, noteC3)
        template.forget(.masterVolume)
        XCTAssertTrue(template.mappings.isEmpty)
    }

    func testMatching() {
        var template = MIDIControllerTemplate(name: "Pads")
        template.learn(noteC3, for: .pad(.one))
        let press = MIDIControlMessage(status: 0x99, data1: 48, data2: 100)!
        let release = MIDIControlMessage(status: 0x89, data1: 48, data2: 0)!
        let otherChannel = MIDIControlMessage(status: 0x90, data1: 48, data2: 100)!
        XCTAssertEqual(template.mappings(matching: press).first?.target, .pad(.one))
        XCTAssertEqual(template.mappings(matching: release).first?.target, .pad(.one), "a pad hears its release")
        XCTAssertFalse(release.isPress)
        XCTAssertTrue(template.mappings(matching: otherChannel).isEmpty)
        XCTAssertTrue(MIDIControlTarget.pad(.one).hearsRelease)
        XCTAssertFalse(MIDIControlTarget.fill.hearsRelease)
        XCTAssertTrue(MIDIControlTarget.partPan(.drums).isContinuous)
        XCTAssertFalse(MIDIControlTarget.partMute(.drums).isContinuous)
    }

    func testTemplatesSurviveSavingAndUnknownLinks() throws {
        var template = MIDIControllerTemplate(name: "Mine", deviceNameHint: "Keystation")
        template.learn(noteC3, for: .pad(.seven))
        template.learn(cc7, for: .partVolume(.bass))
        let data = try JSONEncoder().encode([template])
        let back = try JSONDecoder().decode([MIDIControllerTemplate].self, from: data)
        XCTAssertEqual(back, [template])
        // A link to a target a later version added is dropped, not the template.
        var json = String(decoding: data, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"partVolume\"", with: "\"somethingNew\"")
        let lossy = try JSONDecoder().decode([MIDIControllerTemplate].self, from: Data(json.utf8))
        XCTAssertEqual(lossy.first?.mappings.count, 1)
        XCTAssertEqual(lossy.first?.mapping(for: .pad(.seven))?.source, noteC3)
        XCTAssertTrue(template.suits(deviceNamed: "M-Audio Keystation 49"))
    }

    func testNanoKONTROL2Layout() {
        let t = MIDIBuiltInTemplates.nanoKONTROL2
        XCTAssertTrue(t.isBuiltIn)
        XCTAssertTrue(t.suits(deviceNamed: "nanoKONTROL2 SLIDER/KNOB"))
        XCTAssertEqual(t.mapping(for: .partVolume(.plate))?.source.number, 0)
        XCTAssertEqual(t.mapping(for: .partVolume(.bass))?.source.number, 3)
        XCTAssertEqual(t.mapping(for: .masterVolume)?.source.number, 7)
        XCTAssertEqual(t.mapping(for: .rhythmStartStop)?.source.number, 41)
        XCTAssertEqual(t.mapping(for: .rhythmStop)?.source.number, 42)
        XCTAssertEqual(t.mapping(for: .partSolo(.plate))?.source.number, 32, "the strip's S button")
        XCTAssertEqual(t.mapping(for: .partSolo(.bass))?.source.number, 35)
        XCTAssertEqual(Set(t.mappings.map(\.source)).count, t.mappings.count, "no message used twice")
        XCTAssertEqual(Set(t.mappings.map(\.id)).count, t.mappings.count)
    }

    func testScaling() {
        XCTAssertEqual(MIDIControlScaling.gain(forFraction: 0), 0)
        XCTAssertEqual(Double(MIDIControlScaling.gain(forFraction: 1)), pow(10, 6.0 / 20), accuracy: 0.001)
        XCTAssertEqual(MIDIControlScaling.fraction(forGain: MIDIControlScaling.gain(forFraction: 0.7)), 0.7, accuracy: 0.001)
        XCTAssertEqual(MIDIControlScaling.pan(forFraction: 0.5), 0)
        XCTAssertEqual(MIDIControlScaling.tempo(forFraction: 0), AutoStrum.tempoRange.lowerBound)
        XCTAssertEqual(MIDIControlScaling.tempo(forFraction: 1), AutoStrum.tempoRange.upperBound)
    }

    func testPickupWaitsForTheKnobToPassTheValue() {
        var pickup = MIDIPickup()
        let mapping = MIDIControlMapping(source: cc7, target: .tempo, pickup: true)
        XCTAssertFalse(pickup.shouldApply(mapping, incoming: 0.1, current: 0.5))
        XCTAssertFalse(pickup.shouldApply(mapping, incoming: 0.3, current: 0.5))
        XCTAssertTrue(pickup.shouldApply(mapping, incoming: 0.6, current: 0.5), "crossed the value")
        let direct = MIDIControlMapping(source: cc7, target: .tempo)
        XCTAssertTrue(pickup.shouldApply(direct, incoming: 0.0, current: 0.9))
    }

    func testClockTempo() {
        var clock = MIDIClockTempo()
        let gap = 60.0 / 120 / 24   // 120 BPM
        var result: Double?
        for i in 0...24 { result = clock.pulse(at: 10 + Double(i) * gap) }
        XCTAssertEqual(result, 120)
        // Slightly uneven pulses still read steady.
        var wobbly = MIDIClockTempo()
        for i in 0...30 { result = wobbly.pulse(at: Double(i) * gap + (i % 2 == 0 ? 0.0005 : -0.0005)) }
        XCTAssertEqual(result ?? 0, 120, accuracy: 0.5)
        // A pause starts the measuring again.
        XCTAssertNil(clock.pulse(at: 100))
        XCTAssertNil(clock.pulse(at: 100 + gap))
    }
}
