import SwiftUI

/// A test screen for the instrument hosting copied from FWD Sequencer, until the chord
/// pads and strum plate arrive: choose an instrument (built-in or AUv3), open its
/// editor, and hold a test chord to hear it.
struct ContentView: View {
    @StateObject private var store = InstrumentStore()
    @State private var showPicker = false
    @State private var showBuiltInSounds = false
    @State private var showPluginEditor = false
    @State private var showCredits = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            testChords
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .sheet(isPresented: $showPicker) {
            PluginPickerView(
                selectedPlugin: Binding(get: { store.plugin }, set: { store.choose($0) }),
                builtInSound: store.builtInSound
            )
        }
        .sheet(isPresented: $showBuiltInSounds) {
            BuiltInSoundSheet(title: "Built-in Sound", current: store.builtInSound) { sound in
                store.setBuiltInSound(sound)
                // Play the new sound at once, so it can be heard.
                store.noteOn(60)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.noteOff(60) }
            }
        }
        // Full screen, as in FWD Sequencer: a plugin's own window needs the room, and in
        // a sheet it came up at a much smaller scale (Graham, 2026-11-20).
        .fullScreenCover(isPresented: $showPluginEditor) {
            PluginEditorView(trackID: InstrumentStore.partID,
                             trackName: store.instrumentName,
                             onReload: { store.reload() })
        }
        .sheet(isPresented: $showCredits) { CreditsView() }
        // BLOCKING while the instrument loads: interrupting a fragile AUv3 while it
        // instantiates crashes it (FWD lesson 1). Do not add .allowsHitTesting(false).
        .overlay {
            if store.isLoading {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Loading instruments…")
                            .font(.title3.bold()).foregroundStyle(.white)
                        if let name = store.loadingName {
                            Text(name).font(.callout).foregroundStyle(.white)
                        }
                        Text("Some plugins take a while. The screen unlocks when they're ready.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(36)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                .contentShape(Rectangle())
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isLoading)
        .alert("FWD Harp", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("FWD Harp")
                .font(.headline)
                .foregroundStyle(Color(white: 0.87))
            Spacer()
            Button { showPicker = true } label: {
                HStack(spacing: 8) {
                    if let plugin = store.plugin {
                        PluginIcon(plugin: plugin, size: 24)
                    } else {
                        Image(systemName: "pianokeys")
                    }
                    Text(store.instrumentName).lineLimit(1)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(white: 0.87))
                .studioWindow()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Instrument: \(store.instrumentName)")
            .accessibilityHint("Choose another instrument")

            StudioTapButton(title: "EDIT") {
                if store.plugin == nil { showBuiltInSounds = true } else { showPluginEditor = true }
            }
                .accessibilityLabel("Edit Instrument")

            Button { showCredits = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About and Credits")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// The four main chords of C, held to sound, for testing the instrument.
    private var testChords: some View {
        let key = MajorKey(tonic: 0)
        return VStack(spacing: 16) {
            Spacer()
            Text("Test chords: hold one to hear the instrument")
                .font(.callout)
                .foregroundStyle(StudioStyle.scaleText)
            HStack(spacing: 16) {
                ForEach([1, 4, 5, 6], id: \.self) { degree in
                    TestChordButton(chord: key.chord(degree: degree),
                                    preferFlats: key.prefersFlats,
                                    store: store)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Sounds its chord (root position, from middle C up) while held.
private struct TestChordButton: View {
    let chord: Chord
    let preferFlats: Bool
    let store: InstrumentStore
    @State private var sounding: [UInt8] = []

    private var notes: [UInt8] {
        var previous = -1
        return chord.pitchClasses.map { pc in
            var note = 60 + pc
            while note <= previous { note += 12 }
            previous = note
            return UInt8(note)
        }
    }

    var body: some View {
        Text(chord.name(preferFlats: preferFlats))
            .font(.title.bold())
            .foregroundStyle(sounding.isEmpty ? Color(white: 0.87) : .black)
            .frame(width: 130, height: 110)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(sounding.isEmpty
                          ? AnyShapeStyle(LinearGradient(colors: [StudioStyle.capTop, StudioStyle.capBottom],
                                                          startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(StudioStyle.displayText))
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.55), radius: 2, y: 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard sounding.isEmpty else { return }
                        sounding = notes
                        for note in sounding { store.noteOn(note) }
                    }
                    .onEnded { _ in release() }
            )
            .onDisappear { release() }
            .accessibilityLabel("Test chord \(chord.name(preferFlats: preferFlats))")
    }

    private func release() {
        for note in sounding { store.noteOff(note) }
        sounding = []
    }
}

#Preview {
    ContentView()
}
