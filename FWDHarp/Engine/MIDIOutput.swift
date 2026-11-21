import Foundation
import CoreMIDI

/// One MIDI destination that can be sent to directly: a hardware port (USB or
/// Bluetooth) or another app's MIDI input.
nonisolated struct MIDIDestinationInfo: Identifiable, Equatable {
    let id: Int32        // CoreMIDI unique ID, the same across launches
    let name: String
}

/// Sends FWD Harp's MIDI. A virtual source named "FWD Harp" that other apps can
/// choose as their input, and, for destinations chosen in the MIDI settings, sent
/// straight to them too.
///
/// Thread-safe: notes come from the main thread (the plate) and from auto-strum's own
/// queue. Every message is sent at once, never stamped ahead (FWD lesson 5).
nonisolated final class MIDIOutput: @unchecked Sendable {
    static let shared = MIDIOutput()

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var port = MIDIPortRef()
    private let lock = NSLock()
    /// Guarded by `lock`: the destinations sent to directly.
    private var destinationIDs: Set<Int32> = []
    /// Called on the main thread when devices come or go, so the list can be redrawn.
    var onSetupChanged: (() -> Void)?

    private init() {
        let status = MIDIClientCreateWithBlock("FWD Harp Out" as CFString, &client) { [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { self?.onSetupChanged?() }
        }
        guard status == noErr else {
            NSLog("[FWD Harp] MIDI out unavailable: %d", status)
            return
        }
        if MIDISourceCreate(client, "FWD Harp" as CFString, &source) != noErr { source = 0 }
        if MIDIOutputPortCreate(client, "FWD Harp Out" as CFString, &port) != noErr { port = 0 }
    }

    /// Every destination there is now, except FWD Harp's own input.
    func availableDestinations() -> [MIDIDestinationInfo] {
        var result: [MIDIDestinationInfo] = []
        for index in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }
            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            let text = (name?.takeRetainedValue() as String?) ?? "MIDI Destination"
            // FWD Harp's own keyboard input: sending to it would play our own notes back.
            guard !text.hasPrefix("FWD Harp") else { continue }
            result.append(MIDIDestinationInfo(id: uniqueID, name: text))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setDestinations(_ ids: [Int32]) {
        lock.lock(); destinationIDs = Set(ids); lock.unlock()
    }

    /// Send one message (up to three bytes, or several messages run together).
    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, bytes.count <= 256 else { return }
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        let added = bytes.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<MIDIPacket>? in
            guard let base = buffer.baseAddress else { return nil }
            return MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0,
                                     bytes.count, base)
        }
        guard added != nil else { return }
        if source != 0 { MIDIReceived(source, &packetList) }
        lock.lock(); let ids = destinationIDs; lock.unlock()
        guard port != 0, !ids.isEmpty else { return }
        for id in ids {
            var object = MIDIObjectRef()
            var type = MIDIObjectType.destination
            guard MIDIObjectFindByUniqueID(id, &object, &type) == noErr, type == .destination else { continue }
            MIDISend(port, MIDIEndpointRef(object), &packetList)
        }
    }
}
