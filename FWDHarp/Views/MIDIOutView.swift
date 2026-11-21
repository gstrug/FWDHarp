import SwiftUI

/// MIDI out settings: on or off, FWD Harp's own sound, each part's channel, and the
/// destinations sent to directly.
struct MIDIOutView: View {
    @ObservedObject var store: InstrumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [MIDIDestinationInfo] = []

    private var settings: MIDIOutSettings { store.midiOut }

    private func change(_ body: (inout MIDIOutSettings) -> Void) {
        var copy = settings
        body(&copy)
        store.setMIDIOut(copy)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Send MIDI", isOn: Binding(get: { settings.enabled },
                                                      set: { on in change { $0.enabled = on } }))
                    Toggle("Play FWD Harp's own sound", isOn: Binding(
                        get: { settings.internalSound },
                        set: { on in change { $0.internalSound = on } }))
                } footer: {
                    Text("Other apps can choose \"FWD Harp\" as their MIDI input. "
                         + "Switch FWD Harp's own sound off to use it purely as a controller.")
                }

                Section {
                    ForEach(HarpPart.allCases, id: \.self) { part in
                        Picker(part.title, selection: Binding(
                            get: { settings.channel(for: part) },
                            set: { channel in change { $0.setChannel(channel, for: part) } })) {
                            ForEach(Array(MIDIOutSettings.channelRange), id: \.self) { channel in
                                Text("Channel \(channel)").tag(channel)
                            }
                        }
                    }
                } header: {
                    Text("Channels")
                } footer: {
                    Text("Each part on its own channel, so they can play different instruments "
                         + "in another app. Channel 10 is kept for drums, by custom.")
                }

                Section {
                    if destinations.isEmpty {
                        Text("No MIDI devices or app inputs found").foregroundStyle(.secondary)
                    } else {
                        ForEach(destinations) { destination in
                            Toggle(destination.name, isOn: Binding(
                                get: { settings.destinations.contains(destination.id) },
                                set: { on in
                                    change { s in
                                        s.destinations.removeAll { $0 == destination.id }
                                        if on { s.destinations.append(destination.id) }
                                    }
                                }))
                        }
                    }
                } header: {
                    Text("Also send directly to")
                } footer: {
                    Text("Hardware connected by USB or Bluetooth, and apps that offer a MIDI input. "
                         + "Not needed for an app that chooses FWD Harp as its input.")
                }
                .disabled(!settings.enabled)
            }
            .navigationTitle("MIDI Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: refresh)
            .onDisappear { MIDIOutput.shared.onSetupChanged = nil }
        }
    }

    private func refresh() {
        destinations = MIDIOutput.shared.availableDestinations()
        MIDIOutput.shared.onSetupChanged = {
            destinations = MIDIOutput.shared.availableDestinations()
        }
    }
}
