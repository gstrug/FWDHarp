import SwiftUI

/// MIDI settings, laid out as FWD Sequencer's (2026-11-22): the controllers connected
/// and the template each uses, the templates, MIDI clock in, then MIDI out — on or
/// off, each part's channel and own sound, and the destinations sent to directly.
struct MIDISettingsView: View {
    @ObservedObject var player: HarpPlayer
    @ObservedObject private var center = MIDIControlCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [MIDIDestinationInfo] = []
    /// The template being renamed, and the name being typed.
    @State private var renaming: MIDIControllerTemplate?
    @State private var newName = ""

    private var store: InstrumentStore { player.store }

    private var settings: MIDIOutSettings { store.midiOut }

    private func change(_ body: (inout MIDIOutSettings) -> Void) {
        var copy = settings
        body(&copy)
        store.setMIDIOut(copy)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Learn, first and in plain sight: in the toolbar it showed as an icon
                // only, which Graham did not see (2026-11-22).
                Section {
                    Button {
                        startLearn()
                    } label: {
                        Label("Start MIDI Learn", systemImage: "dot.radiowaves.left.and.right")
                            .font(.body.bold())
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("MIDI Learn")
                } footer: {
                    Text("Closes this menu. Tap a control on screen, then move or press the one on your controller to link them. Tap Done on the orange strip when finished.")
                }
                slideSection
                controllersSection
                templatesSection
                clockSection

                Section {
                    Toggle("Send MIDI", isOn: Binding(get: { settings.enabled },
                                                      set: { on in change { $0.enabled = on } }))
                } header: {
                    Text("MIDI Out")
                } footer: {
                    Text("Other apps can choose \"FWD Harp\" as their MIDI input.")
                }

                // One row per part: its MIDI channel and whether FWD Harp plays it too.
                Section {
                    ForEach(HarpPart.allCases, id: \.self) { part in
                        HStack(spacing: 16) {
                            Text(part.title)
                            Spacer()
                            Picker("\(part.title) channel", selection: Binding(
                                get: { settings.channel(for: part) },
                                set: { channel in change { $0.setChannel(channel, for: part) } })) {
                                ForEach(Array(MIDIOutSettings.channelRange), id: \.self) { channel in
                                    Text("Channel \(channel)").tag(channel)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            Toggle("Own sound", isOn: Binding(
                                get: { settings.playsOwnSound(part) },
                                set: { on in change { $0.setPlaysOwnSound(on, for: part) } }))
                                .fixedSize()
                                .accessibilityLabel("Play \(part.title) in FWD Harp too")
                        }
                    }
                } header: {
                    Text("Parts")
                } footer: {
                    Text("Each part on its own channel, so they can play different instruments in another "
                         + "app (drums on 10, the General MIDI custom). Own sound off: hear that part only in "
                         + "the other app; all off makes FWD Harp purely a controller.")
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
            .navigationTitle("MIDI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Learn") { startLearn() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Template Name", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let t = renaming { center.rename(t.id, to: newName) }
                    renaming = nil
                }
            }
            .onAppear(perform: refresh)
            .onDisappear { MIDIOutput.shared.onSetupChanged = nil }
        }
    }

    /// Learn happens on the harp's screen, so close this to get there (the only Learn
    /// switch: Graham, 2026-11-22, not on the top bar).
    private func startLearn() {
        center.learn.isOn = true
        dismiss()
    }

    // MARK: Strum plate slide

    /// What sliding a held finger sideways on the plate sends (Graham, 2026-11-23).
    private var slideSection: some View {
        Section {
            Picker(selection: Binding(get: { player.plateSlide }, set: { player.setPlateSlide($0) })) {
                ForEach(PlateSlide.allCases, id: \.self) { slide in
                    Text(slide.title).tag(slide)
                }
            } label: {
                Label("Slide Sends", systemImage: "hand.draw")
            }
            Picker("Strength", selection: Binding(get: { player.slideDepth }, set: { player.setSlideDepth($0) })) {
                ForEach(SlideDepth.allCases, id: \.self) { depth in
                    Text(depth.title).tag(depth)
                }
            }
            .pickerStyle(.segmented)
            .disabled(player.plateSlide == .off)
        } header: {
            Text("Strum Plate Slide")
        } footer: {
            Text("Slide a finger left or right while it holds a string. Expression swells and softens the sound; Pitch Bend gives a vibrato; Mod Wheel and Aftertouch do whatever the instrument has them do (often vibrato or brightness). They go to the plate's instrument and, with MIDI out on, its channel. An instrument that ignores the one chosen won't change: try another.")
        }
    }

    // MARK: Controllers (as FWD's)

    private var controllersSection: some View {
        Section {
            if center.sources.isEmpty {
                Text("No MIDI controllers connected. Plug one in over USB, or pair a Bluetooth MIDI device, and it appears here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(center.sources) { source in
                controllerRow(source)
            }
        } header: {
            Text("Controllers")
        } footer: {
            Text("Each controller uses one template. Load switches it to another; Save As keeps its current links under a new name. Links you make with MIDI Learn are saved into the template straight away. The nanoKONTROL2 is set up automatically. Keys → Plate plays the plate's instrument from the controller's keys, with sustain, pitch bend, mod wheel and aftertouch; keys linked with Learn keep doing what they are linked to.")
        }
    }

    private func controllerRow(_ source: MIDIInputManager.Source) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ActivityLight(lastActivity: center.lastActivity[source.name])
                Text(source.name).font(.body.bold()).lineLimit(1)
                Spacer()
                Toggle("Use", isOn: Binding(
                    get: { center.isEnabled(source.name) },
                    set: { center.setDevice(source.name, enabled: $0) }
                ))
                .labelsHidden()
            }
            HStack(spacing: 10) {
                Text("Template").foregroundStyle(.secondary)
                Text(center.template(forDevice: source.name)?.name ?? "None")
                    .bold().lineLimit(1)
                Spacer(minLength: 8)
                Menu {
                    loadChoices(forDevice: source.name)
                } label: {
                    Label("Load", systemImage: "folder")
                }
                Button { saveAs(forDevice: source.name) } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down")
                }
            }
            // Bordered so each button takes its own taps; in a Form row plain buttons
            // would all fire together.
            .buttonStyle(.bordered)
            .disabled(!center.isEnabled(source.name))

            Toggle(isOn: Binding(get: { center.keysPlayPlate(source.name) },
                                 set: { center.setKeysPlayPlate($0, forDevice: source.name) })) {
                Label("Keys → Plate", systemImage: "pianokeys")
            }
            .disabled(!center.isEnabled(source.name))
        }
        .padding(.vertical, 2)
    }

    /// Templates to load onto a controller, the current one ticked.
    @ViewBuilder
    private func loadChoices(forDevice name: String) -> some View {
        let current = center.template(forDevice: name)?.id
        Button { center.assign(nil, toDevice: name) } label: {
            if current == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
        }
        Divider()
        ForEach(center.templates) { t in
            Button { center.assign(t.id, toDevice: name) } label: {
                if current == t.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
            }
        }
    }

    /// Keep a controller's current links under a new name and switch it to that copy.
    private func saveAs(forDevice name: String) {
        let copy: MIDIControllerTemplate
        if let current = center.template(forDevice: name),
           let duplicate = center.duplicate(current.id) {
            copy = duplicate
        } else {
            copy = center.newTemplate(named: name, deviceNameHint: name)
        }
        center.assign(copy.id, toDevice: name)
        newName = copy.name
        renaming = copy
    }

    // MARK: Templates (as FWD's)

    private var templatesSection: some View {
        Section {
            ForEach(center.templates) { template in
                NavigationLink {
                    MIDITemplateDetailView(templateID: template.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                        Text(usage(of: template))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contextMenu { actions(for: template) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !template.isBuiltIn {
                        Button(role: .destructive) { center.delete(template.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    Button { saveAs(template) } label: {
                        Label("Save As", systemImage: "plus.square.on.square")
                    }
                    .tint(.blue)
                }
            }
        } header: {
            Text("Templates")
        } footer: {
            Text("Learning on a factory template makes your own copy first, so the factory one stays as it was. Tap a template to see its links; swipe or long press it to save a copy, rename or delete it.")
        }
    }

    @ViewBuilder
    private func actions(for template: MIDIControllerTemplate) -> some View {
        Button { saveAs(template) } label: {
            Label("Save As…", systemImage: "plus.square.on.square")
        }
        if !template.isBuiltIn {
            Button {
                newName = template.name
                renaming = template
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button(role: .destructive) { center.delete(template.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func saveAs(_ template: MIDIControllerTemplate) {
        guard let copy = center.duplicate(template.id) else { return }
        newName = copy.name
        renaming = copy
    }

    private func usage(of template: MIDIControllerTemplate) -> String {
        let links = "\(template.mappings.count) link\(template.mappings.count == 1 ? "" : "s")"
        let users = center.sources.filter { center.template(forDevice: $0.name)?.id == template.id }
        guard !users.isEmpty else { return links }
        return links + " · used by " + users.map(\.name).joined(separator: ", ")
    }

    // MARK: Clock in

    private var clockSection: some View {
        Section {
            Toggle(isOn: clockBinding(\.follow)) {
                Label("Follow MIDI Clock", systemImage: "metronome")
            }
            Picker(selection: Binding(get: { center.clock.source ?? "" },
                                      set: { name in
                                          var settings = center.clock
                                          settings.source = name.isEmpty ? nil : name
                                          center.setClock(settings)
                                      })) {
                Text("Any").tag("")
                ForEach(center.sources) { source in
                    Text(source.name).tag(source.name)
                }
                // A device chosen before, not connected now, stays chosen.
                if let chosen = center.clock.source, !center.sources.contains(where: { $0.name == chosen }) {
                    Text("\(chosen) (not connected)").tag(chosen)
                }
            } label: {
                Label("From", systemImage: "cable.connector")
            }
            .disabled(!center.clock.follow)
            Toggle(isOn: clockBinding(\.transport)) {
                Label("Start and Stop the Drums", systemImage: "play.square")
            }
            .disabled(!center.clock.follow)
            if center.clock.follow {
                HStack {
                    Text("Tempo").foregroundStyle(.secondary)
                    Spacer()
                    Text(player.clockTempo.map { String(format: "%.1f BPM", $0) } ?? "Waiting for clock…")
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Clock In")
        } footer: {
            Text("Follows another app's or a drum machine's tempo and beat: auto-strum, the drums and the bass play in time with it. With Start and Stop on, its play and stop buttons start and stop the drums. If the clock stops arriving, FWD Harp carries on at the last tempo.")
        }
    }

    private func clockBinding(_ flag: WritableKeyPath<MIDIClockSettings, Bool>) -> Binding<Bool> {
        Binding(get: { center.clock[keyPath: flag] },
                set: { value in
                    var settings = center.clock
                    settings[keyPath: flag] = value
                    center.setClock(settings)
                })
    }

    private func refresh() {
        destinations = MIDIOutput.shared.availableDestinations()
        MIDIOutput.shared.onSetupChanged = {
            destinations = MIDIOutput.shared.availableDestinations()
        }
    }
}

/// One template's links, listed. A user template's links can be removed here.
private struct MIDITemplateDetailView: View {
    let templateID: UUID
    @ObservedObject private var center = MIDIControlCenter.shared

    private var template: MIDIControllerTemplate? {
        center.templates.first { $0.id == templateID }
    }

    var body: some View {
        List {
            if let template {
                if template.mappings.isEmpty {
                    Text("No links yet. Turn on Learn, tap a control, then move or press the one on your controller.")
                        .foregroundStyle(.secondary)
                }
                ForEach(template.mappings) { mapping in
                    HStack {
                        Text(mapping.target.displayName)
                        Spacer()
                        Text(mapping.source.displayName)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if !template.isBuiltIn {
                            Button(role: .destructive) {
                                center.removeLink(mapping.target, fromTemplate: template.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(template?.name ?? "Template")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lit briefly whenever a controller sends something, so you can see it is connected
/// and which one a knob belongs to.
private struct ActivityLight: View {
    let lastActivity: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let lit = lastActivity.map { context.date.timeIntervalSince($0) < 0.25 } ?? false
            Circle()
                .fill(lit ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)
                .shadow(color: lit ? .green : .clear, radius: 3)
        }
        .accessibilityHidden(true)
    }
}
