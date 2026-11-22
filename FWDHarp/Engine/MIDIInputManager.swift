import Foundation
import CoreMIDI
import os

/// Receives MIDI from every connected controller and keyboard. Copied from FWD
/// Sequencer on 2026-11-20.
///
/// This listens to every MIDI
/// source the iPad can see — USB controllers like the nanoKONTROL2 and X-Station,
/// Bluetooth MIDI, other apps' virtual outputs — and follows them coming and going.
/// It decodes channel messages and hands them on; InstrumentStore plays
/// them on the instrument.
///
/// `onMessage` is called on CoreMIDI's own receive thread, not the main thread, and must
/// return quickly. Nothing here touches the audio graph.
nonisolated final class MIDIInputManager: @unchecked Sendable {
    static let shared = MIDIInputManager()

    struct Source: Identifiable, Hashable, Sendable {
        /// CoreMIDI's unique id for the endpoint — stable while it stays connected.
        let id: Int32
        let name: String
    }

    /// Called on the CoreMIDI receive thread for each CC / note message.
    /// @Sendable so it is never taken to belong to the main actor: it runs off it.
    var onMessage: (@Sendable (Source, MIDIControlMessage) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onMessage }
        set { lock.lock(); _onMessage = newValue; lock.unlock() }
    }
    /// Called on the main thread whenever the set of sources changes.
    var onSourcesChanged: (([Source]) -> Void)?

    /// Called on the CoreMIDI receive thread for pitch bend and aftertouch, which
    /// cannot be linked to controls but are played through to instruments.
    var onPerformanceMessage: (@Sendable (Source, UInt8, UInt8, UInt8) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onPerformanceMessage }
        set { lock.lock(); _onPerformanceMessage = newValue; lock.unlock() }
    }

    /// Called on the CoreMIDI receive thread for MIDI clock and transport: 0xF8 clock,
    /// 0xFA start, 0xFB continue, 0xFC stop, with when it was sent (host time, seconds).
    var onRealtime: (@Sendable (Source, UInt8, Double) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onRealtime }
        set { lock.lock(); _onRealtime = newValue; lock.unlock() }
    }

    private let lock = OSAllocatedUnfairLock()
    private var _onRealtime: (@Sendable (Source, UInt8, Double) -> Void)?
    private var _onMessage: (@Sendable (Source, MIDIControlMessage) -> Void)?
    private var _onPerformanceMessage: (@Sendable (Source, UInt8, UInt8, UInt8) -> Void)?
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    /// Connection token → source. The token rides along with every packet as the
    /// connection refCon, so the receive block can say which device it came from.
    private var sourcesByToken: [Int: Source] = [:]
    private var tokensByEndpoint: [MIDIEndpointRef: Int] = [:]
    private var nextToken = 1
    private(set) var sources: [Source] = []
    private var started = false

    private init() {}

    /// Create the client and port and connect everything. Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true
        let status = MIDIClientCreateWithBlock("FWD Harp Input" as CFString, &client) { [weak self] notification in
            // Devices plugged in or removed: reconnect on the main thread.
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.refreshSources() }
            }
        }
        guard status == noErr else { started = false; return }
        let portStatus = MIDIInputPortCreateWithProtocol(
            client, "FWD Harp Keys" as CFString, ._1_0, &port
        ) { [weak self] eventList, refCon in
            self?.receive(eventList, token: Int(bitPattern: refCon))
        }
        guard portStatus == noErr else { started = false; return }
        refreshSources()
    }

    /// Connect to every source that is present and not already connected; forget the
    /// ones that have gone.
    func refreshSources() {
        guard started else { return }
        var present: [MIDIEndpointRef] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            present.append(endpoint)
        }

        lock.lock()
        // Gone: disconnect and drop.
        for (endpoint, token) in tokensByEndpoint where !present.contains(endpoint) {
            MIDIPortDisconnectSource(port, endpoint)
            tokensByEndpoint.removeValue(forKey: endpoint)
            sourcesByToken.removeValue(forKey: token)
        }
        // New: connect.
        for endpoint in present where tokensByEndpoint[endpoint] == nil {
            let name = Self.displayName(of: endpoint)
            // The app's own MIDI out will be a source too (coming with the brief's MIDI
            // out); listening to ourselves would play every note twice.
            guard !name.hasPrefix("FWD Harp") else { continue }
            let token = nextToken
            nextToken += 1
            let source = Source(id: Self.uniqueID(of: endpoint), name: name)
            tokensByEndpoint[endpoint] = token
            sourcesByToken[token] = source
            MIDIPortConnectSource(port, endpoint, UnsafeMutableRawPointer(bitPattern: token))
        }
        let list = sourcesByToken.values.sorted { $0.name < $1.name }
        sources = list
        lock.unlock()

        onSourcesChanged?(list)
    }

    // MARK: Receiving

    private func receive(_ eventList: UnsafePointer<MIDIEventList>, token: Int) {
        lock.lock()
        let source = sourcesByToken[token]
        let handler = _onMessage
        let performance = _onPerformanceMessage
        let realtime = _onRealtime
        lock.unlock()
        guard let source, let handler else { return }

        for packet in eventList.unsafeSequence() {
            let wordCount = Int(packet.pointee.wordCount)
            // When it was sent, for the clock's tempo: CoreMIDI's stamp, or now.
            let stamp = packet.pointee.timeStamp
            let time = Self.seconds(hostTime: stamp == 0 ? mach_absolute_time() : stamp)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                var i = 0
                while i < min(wordCount, words.count) {
                    let word = words[i]
                    let type = word >> 28
                    // Type 2: a MIDI 1.0 channel-voice message in one word. The port
                    // was opened for MIDI 1.0, so that is what controllers arrive as.
                    // Type 1: system real-time, the clock and transport.
                    if type == 0x1 {
                        let status = UInt8((word >> 16) & 0xFF)
                        if status == 0xF8 || status == 0xFA || status == 0xFB || status == 0xFC {
                            realtime?(source, status, time)
                        }
                    } else if type == 0x2 {
                        let status = UInt8((word >> 16) & 0xFF)
                        let data1 = UInt8((word >> 8) & 0x7F)
                        let data2 = UInt8(word & 0x7F)
                        if let message = MIDIControlMessage(status: status, data1: data1, data2: data2) {
                            handler(source, message)
                        } else {
                            // Compared directly: this runs for every message on
                            // CoreMIDI's thread, and an array here was built each time.
                            let kind = status & 0xF0
                            if kind == 0xE0 || kind == 0xA0 || kind == 0xD0 {
                                performance?(source, status, data1, data2)
                            }
                        }
                    }
                    i += Self.wordsInMessage(ofType: type)
                }
            }
        }
    }

    /// Universal MIDI Packet sizes by message type, so a packet holding several
    /// messages — or ones this ignores — is walked correctly.
    private static func wordsInMessage(ofType type: UInt32) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4
        }
    }

    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    /// Host time (mach ticks) in seconds.
    static func seconds(hostTime: UInt64) -> Double { Double(hostTime) * timebase }

    // MARK: Endpoint properties

    private static func displayName(of endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
           let value = name?.takeRetainedValue() {
            return value as String
        }
        return "MIDI Device"
    }

    private static func uniqueID(of endpoint: MIDIEndpointRef) -> Int32 {
        var id: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
        return id
    }
}
