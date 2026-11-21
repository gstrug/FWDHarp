import Foundation
import Combine
import os

// Copied from FWD Sequencer (PlaybackMonitor.swift) on 2026-11-21: the mixer's meters.

/// Audio levels for the meters (~20 a second), on an object of their own so a meter
/// update redraws only the meters, not the whole screen.
final class LevelMonitor: ObservableObject {
    @Published var trackLevels: [UUID: AudioLevel] = [:]
    @Published var masterLevel: AudioLevel = .silent
}

/// Gathers the levels the audio thread reports and hands them to the main thread in
/// one batch per interval, rather than one main-thread hop per meter per buffer.
nonisolated final class LevelBatcher: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var pendingTracks: [UUID: AudioLevel] = [:]
    private var pendingMaster: AudioLevel?
    private var scheduled = false
    private let interval: TimeInterval
    private let deliver: ([UUID: AudioLevel], AudioLevel?) -> Void

    /// `deliver` runs on the main thread.
    init(interval: TimeInterval = 0.05,
         deliver: @escaping ([UUID: AudioLevel], AudioLevel?) -> Void) {
        self.interval = interval
        self.deliver = deliver
    }

    func track(_ id: UUID, _ level: AudioLevel) {
        lock.lock(); pendingTracks[id] = level; let start = claimFlush(); lock.unlock()
        if start { scheduleFlush() }
    }

    func master(_ level: AudioLevel) {
        lock.lock(); pendingMaster = level; let start = claimFlush(); lock.unlock()
        if start { scheduleFlush() }
    }

    /// Caller holds the lock. True for the item that should schedule the flush.
    private func claimFlush() -> Bool {
        guard !scheduled else { return false }
        scheduled = true
        return true
    }

    private func scheduleFlush() {
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            lock.lock()
            let tracks = pendingTracks, master = pendingMaster
            pendingTracks = [:]; pendingMaster = nil; scheduled = false
            lock.unlock()
            deliver(tracks, master)
        }
    }
}
