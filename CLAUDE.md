# FWD Harp — project briefing for Claude

Read this first in any new session. Started 2026-11-20 as a new app beside FWD
Sequencer, reusing its well-tested parts. If this file disagrees with the code, the
code wins — then fix this file.

## Who and how we work

- Owner: Graham Struwig. **Not a programmer.** He relies on Claude to run git, edit
  the Xcode project, build checks and push to GitHub. Explain in plain words, do the
  technical steps yourself, and say what you did. When he must do something himself
  (Xcode, App Store Connect, github.com), talk him through it click by click.
- Personal project. GitHub: `gstrug/FWDHarp`, branch `main`.
- Apple developer team `8MDY92DSB9`, bundle id `com.grahamstruwig.FWDHarp`.
- Version 1.0, build 4 (TestFlight 2026-11-23; build 2 was the first, 2026-11-21). Every TestFlight upload needs `CURRENT_PROJECT_VERSION`
  bumped first (Debug and Release), committed as "Bump build to NN for TestFlight".
- Commit often with plain-English messages stating *why*. Author commits as
  `Graham Struwig <g.struwig@gmail.com>`.
- **Open `FWDHarp.xcodeproj`**, not the folder or `Package.swift` (that is the
  test-only core package; it builds but cannot run).
- **Deployment target stays iPadOS 16.6**, iPad only (`TARGETED_DEVICE_FAMILY = 2`).
  Decline Xcode's "Update to recommended settings": on FWD it changed the target and
  broke the GitHub build.
- **This Xcode (27) makes new projects without the usual form**: File ▸ New ▸ Project
  opens an "Untitled Project"; it is named when saved. Its defaults (iPhone, Mac,
  Vision Pro, iOS 27, a placeholder bundle id, `objectVersion 90`) were all replaced
  on 2026-11-20 with FWD's settings (`objectVersion 77`).

### Release workflow — Graham's rule (same as FWD)

1. Make the change and **commit locally only**. **Do not push to GitHub.**
2. Graham builds from Xcode and tests on his iPad.
3. When he says so: bump the build number, commit, **then push**.
4. Graham archives and uploads to TestFlight himself.

### How Claude reaches the code

- The folder on Graham's Mac (`~/Desktop/FWDHarp`) is connected to the session; edits
  and commits happen there through the device shell (a Linux sandbox: no Xcode, no
  `swift`, no GitHub). Git there needs delete permission on the folder (git removes its
  own lock files), so ask for it before the first commit.
- To push: `git bundle create .build/claude-transfer.bundle origin/main..main` on the
  Mac (the whole `main` for the first push), stage the bundle to the cloud workspace,
  fetch it into a cloud clone of `gstrug/FWDHarp` and push from there. Then
  `git update-ref refs/remotes/origin/main <sha>` on the Mac.
- **Test branch (Graham agreed 2026-11-20):** to compile-check work before Graham
  builds, push it to a `claude/...` branch (never `main`) and run
  `gh workflow run validate.yml --ref claude/<branch>`; fix errors there, then bring the
  commits to the Mac's `main` (still unpushed, per the release rule).
- Bringing commits from the cloud to the Mac: `git bundle` there, then
  `device_commit_files` — it refuses large files (a ~98 MB bundle failed), so `split -b
  20000000` the bundle, commit the parts, `cat` them together on the Mac and fetch.
- GitHub Actions (`Validate`, `.github/workflows/validate.yml`) runs `swift test` and
  Debug and Release simulator builds — the only compile check, since nothing on
  Claude's side runs Xcode. Check with `gh run list`.
- Files added inside `FWDHarp/` join the app automatically (synchronized folder).
  `Info.plist` is excluded from it by an exception in the project file — keep it so,
  or the build fails with two Info.plists. A new pure, testable file also goes in
  `Package.swift`'s `sources`.

## What it is (Graham's description, 2026-11-20)

An iPad **AUv3 instrument and effects host that plays like an electronic chord harp**
(the Suzuki Omnichord is the model — **never use that name**, in the app, its text or
the App Store). Not a sequencer. Same look and feel as FWD Sequencer.

- **Chord pads under the left hand**, in fixed positions that fall naturally under
  the fingers, each showing its chord's name in the chosen key. Graham's sketch:
  top row **4 1 5**, middle row **7 3 6** (the 7th and the minor 3rd and 6th), bottom
  **2** (minor). To be confirmed in the design brief (exact positions, 7 = diminished
  or a dominant 7th, extra chords, how the key is chosen).
- **Strum plate on the right**, played by touch or by strumming across it; it plays
  the held chord's notes up the plate.
- **Strum patterns** for the plate: arpeggiate, chords, alternate and so on. Possibly
  **scales** on the plate.
- **MIDI out**, so it can be used as a controller for other apps and hardware.

## Reuse from FWD Sequencer (copied, not shared)

FWD Harp gets its own copies; FWD stays untouched and a fix in one cannot break the
other. Graham still visits FWD for fixes. Candidates, from `~/Desktop/FwdSequencer`:
`Engine/AudioEngineManager.swift` (plugin hosting, effects chain, state capture, load
protection — strip the sequencer parts), `Engine/PluginManager.swift`,
`Engine/PluginLoadTracker.swift`, `Bridge/` (exception catcher, view hosting),
`Views/PluginEditorView.swift`, plugin pickers, `TrackEffectsView`, the GM sound bank
(`SoundBank/` parts + the "Join sound bank" build phase + licences + Credits), MIDI
input (`Engine/MIDIInputManager.swift`, `Models/MIDIControl.swift`,
`Store/MIDIControlCenter.swift` — Learn, templates, key routing incl. Transpose and
Lowest/Highest Note), `Views/StudioControls.swift` (the look), help mode
(`HelpMode.swift`, `HelpTopics.swift` — new wording for this app), saving with backups
and quarantine (`Store/SongPersistence.swift`). Bring each with its tests.

## Hard-won lessons from FWD (do not re-learn these)

1. **Plugin loading is fragile.** Generation-tokened loads with a 30 s timeout and GM
   fallback, per-track MIDI suspension (reference-counted; a superseded load must hand
   its suspend back), and a *blocking* "Loading instruments…" overlay. Effects need a
   timeout too.
2. **Don't transform plugin views** (pinch-zoom): out-of-process UIs go blank. Size
   them with Auto Layout.
3. **Plugin state** is a binary plist; trust `fullState` only with a data payload.
   Capture only at safe moments, and **only instruments whose sound may have changed**
   (chosen fresh or editor opened) — a plugin that ignored its restore on a cold start
   otherwise has its default saved over the user's patch.
4. **Thread safety:** engine dictionaries behind one lock; saving must never mutate
   the document.
5. **Don't stamp AUv3 notes with future sample times** (plugins have their own render
   timeline). Flush on stop only.
6. **Unit tests can't hear.** Anything touching timing or plugins is checked on a
   real iPad with real plugins before building on it.
7. **AVAudioUnitSampler drops its sound bank when rewired** (adding an effect): reload
   the bank after every chain rebuild.
8. **GeoShred** is not reliably hostable; if any plugin is slow, check its own app first
   (GeoShred was held up by a promo video in its app).
9. **Effects that refuse a format** raise an NSException on connect: connect through
   the Objective-C catcher and a converter mixer.
10. Graham's playing: left-hand chords, right-hand broken chords. Live-key features
    (like FWD's Lowest Note) were reworked three times before they suited him — build
    the simplest version, let him play it, then adjust.

## Build and test

- Open `FWDHarp.xcodeproj`, scheme `FWDHarp`, run on the iPad.
- `swift test` for the portable core (`Package.swift`, `Tests/FWDHarpCoreTests`).
- AUv3 hosting must be tested on a physical iPad with plugins installed.

## Where things stand

- 2026-11-20: project created and set up like FWD (settings, Info.plist, entitlements,
  test package with `Models/Harmony.swift` — the seven chords of a major key and their
  names — and the GitHub check). Placeholder screen. Next: a design brief with Graham,
  then copy FWD's hosting and MIDI in, then the pads and strum plate.
- 2026-11-20: first push to GitHub (`origin` added, Validate passed). Design brief
  agreed with Graham: Claude Doc "FWD Harp — Design Brief"
  (https://claude.ai/artifact/F8jjZ3bSxbZqy3Gmfetmut). Key points: pads 7(pinky,
  a hold-only 7th modifier: dominant 7ths on majors, m7 on minors) 4 1 5 on top,
  thumb 6 3 with 2 below; no diminished chord; Hold latches the chord; plate is a
  tall strip, low at the bottom, louder to the right, adjustable range; scales limit
  the plate's notes; four auto-strum patterns; tempo by slider, tap, MIDI clock, Link;
  MIDI out to apps and hardware with a mute-internal switch.
- 2026-11-20: FWD's instrument hosting copied in (step 1 of the brief's build order,
  first half): Bridge, PluginManager, PluginLoadTracker, AudioEngineManager (stripped of
  MIDI clock, scheduled notes, delay compensation and recording), plugin picker and
  editor (with its piano keys), StudioControls, GM sound bank + "Join sound bank" phase,
  licences, Credits, PrivacyInfo. `Store/InstrumentStore.swift` holds the one instrument
  (fixed part id, default GM 46 Orchestral Harp; not saved yet). `ContentView` is a test
  screen: instrument chip, EDIT, hold-to-sound test chords C F G Am. Compiles on GitHub.
  Then (same day): saving (`Models/HarpSetup.swift`, `Store/SetupStorage.swift`: one
  setup in Application Support/Setup, backup + quarantine, saved 1 s after a change and on
  backgrounding; instrument patch captured on editor close/background only if
  `mayHaveNewState`), effects (`Views/EffectsView.swift`, FX chip; effect editors full
  screen), MIDI keyboard input playing the instrument (`Engine/MIDIInputManager.swift`,
  `Models/MIDIMessage.swift`). Plugin editors open with `.fullScreenCover`, as in FWD
  (a sheet made them small). Deferred until the pads/plate exist: MIDI Learn
  (MIDIControlCenter) and help mode, which need the harp's own controls.
  Note: the audio buffer is FWD's 23 ms (chosen against crackle); may feel slow for live
  strumming, so check it when the plate exists.
- 2026-11-20: step 2, first playable harp. `Models/Pads.swift` (ChordPad, PadLayout grid
  in pad-widths, PadSelection: last pressed wins, 7 counted apart),
  `Models/StrumPlate.swift` (10 strings = 3 octaves of a triad, bottom string from the
  key's note in octave 3 (48 + tonic), louder to the right 30–127, crossed strings all
  played), `Harmony.swift` gained dominant/minor 7ths, `HarpSetup.keyTonic`.
  `Store/HarpPlayer.swift` plays: pads silent; plucked notes ring until restruck or a
  different chord pad is pressed; the 7 stops nothing; lifting all pads leaves notes
  ringing. Views: `PadsView`, `StrumPlateView`, `MultiTouchSurface` (UIKit, every
  finger, cancellations end touches). KEY menu in the top bar. Not yet: Hold,
  auto-strum, plate patterns, range setting, scales, MIDI out, Learn, help.
- 2026-11-20: pad layout changed after Graham's first play (one pad at a time): two rows
  F C G / Dm Am Em, and a thumb row of smaller modifier pads 7th, sus2, sus4 below-right
  of C. sus replaces the 3rd (minor chords too); with 7th → 7sus2/7sus4; last sus
  pressed wins. Modifiers stop nothing ringing.
- 2026-11-21: step 3. Plate RANGE 3/4/5 octaves (10/13/16 strings in the same height;
  3 is the minimum — Graham likes that spread), OCT ±2 (lowest note 48 + tonic + 12 ×
  shift), both saved in HarpSetup. HOLD (top bar, not saved): PadSelection.latched keeps
  the last chord pad after lifting; modifiers still apply live; the kept pad stays lit.
  Next: auto-strum (four patterns) and tempo.
- Delete permission on the folder is per connection: after the Mac reconnects (e.g.
  overnight) ask for it again BEFORE the first git command, or git leaves .lock files.
- 2026-11-21: step 4 (first part), auto-strum. `Models/AutoStrum.swift` (patterns:
  Arpeggio Up / Up-Down in eighths, Block Chords per beat, Bass + Chord oom-pah, Single
  Sweep per pad press; figure = plate's lowest strings, chord once + root on top; tap
  tempo), `Engine/AutoStrummer.swift` (own queue, steps timed from the start, notes sent
  when due; each step's notes released at the next). AUTO / pattern menu / BPM readout +
  TAP above the pads; pattern and tempo saved, AUTO not. RANGE moved to the top bar
  beside HOLD; OCT above the plate. Still to come: MIDI clock and Link for tempo.
- 2026-11-21: after Graham played auto-strum: tempo changes no longer pause it (each
  step due one interval after the previous one was due, at the tempo then — never
  restart the clock on a change); arpeggios Down and 2-octave Up/Down/Up-Down; Hold
  keeps the modifiers with the kept chord (PadSelection.latchedSeventh /
  latchedSuspension; pressing the pad again takes the modifiers held then); plate note
  orders (PlatePattern: Straight, Alternating, Rolling, Octaves, Bass + Chord) in a
  menu beside OCT, saved; auto-strum builds from the straight order.
- 2026-11-21: added to the brief (not to build yet): a rhythm section — drum styles/genres
  each with a bass line that follows the chord pads, one FILL button (fill to the end of
  the bar). Built LAST. Meanwhile keep tempo one shared clock (MIDI clock/Link) and give
  MIDI out its own channel for chords/plate, so drums (ch 10) and bass can join later.
- 2026-11-21: Hold + auto-strum: pressing the kept pad again retriggers the pattern
  (AutoStrummer.retrigger; sweeps again). Hold: a second tap on a kept modifier takes
  it off (PadSelection.keepsModifiers → latched toggles). Scales: PlateScale (Chord,
  Major, Pentatonic = major pent., Blues = minor blues, Natural Minor = relative minor,
  Chromatic) in a SCALE menu after RANGE; plays without a pad; strings = every scale
  note across the range (Major 3 oct = 22); plate orders apply (Bass + Chord → Straight);
  auto-strum still plays the chord. Saved. Next: MIDI out.
- 2026-11-21: two parts (HarpPart .plate/.auto), each PartSound (instrument, patch,
  built-in, effects) + ChannelMix (volume, pan, mute); masterVolume. The plate's sound
  stays in HarpSetup's old flat fields (old setups open unchanged); `autoSound` nil =
  auto-strum plays through the plate's track (default; OWN SOUND gives it one, GM 24).
  Track ids: plate …A1 (unchanged), auto …A2. AutoStrummer.setTarget follows. MIX
  button → `Views/MixerView.swift` (strips: instrument/EDIT/FX via
  `PartInstrumentButtons`, pan knob, fader + meter, M; master). Meters: LevelMonitor +
  LevelBatcher copied from FWD. `.loadingOverlay(store)` / `.storeNotices(store)` on the
  main screen AND the mixer sheet. Next: MIDI out (a channel per part).
- 2026-11-21: PANIC (HarpPlayer.panic → strummer.stop + engine.panic). Plate and
  auto-strum always send note-off before note-on (same note on the same instrument could
  stack note-ons and hang). Mixer is now `MixerPanel`, shown in place of the pads while
  MIX is lit (plate stays playable); master strip first, all strips one size
  (StripSize) so drums/bass strips can join.
- 2026-11-21: "stuck notes" on the plate were the ring-until-chord-change design on
  sustaining synths (and their release tails after PANIC). PlateRing (Short 0.4 s,
  Medium 1.2 s, Long 3 s default, Until Chord) times each pluck's note-off; a restrike
  re-times it (HarpPlayer.plucks). PANIC also sends CC64/120/123 on all 16 channels and
  note-offs in both spellings. Master strip: Color.clear, not EmptyView (no size).
  Velocity path checked in code (30–127 left→right); Graham to confirm on built-in.
- 2026-11-21: PlateRing.whileHeld (new default): note-off when the finger leaves the
  string or lifts, like the editor's audition keys (which Graham found fine where the
  plate's 3 s timer sounded hung). pluck returns the note; PlateTouches lifts that note
  (not the string's current note); HarpPlayer.held counts fingers per note. PANIC toned
  down (glitched at 300+ events): CC120 on ch 1 only, CC64 + CC123 on 16 ch, one
  note-off per note.
- 2026-11-21: HOLD and STOP (PadSelection.releaseKept → ends the kept chord and the
  pattern; HOLD stays on) beside AUTO above the pads. Top bar split to match the screen:
  ⓘ, KEY, RANGE, SCALE, MIX, PANIC over the pads; plate instrument/EDIT/FX in a
  300-wide group over the plate (top bar padding 20, gap 24, like the content).
- 2026-11-21: MIDI out. `Models/MIDIOut.swift` (MIDIOutSettings in HarpSetup.midiOut:
  off by default, internalSound, plate ch 1 / auto ch 2, destinations by CoreMIDI
  unique ID; MIDIBytes), `Engine/MIDIOutput.swift` (virtual source "FWD Harp" +
  MIDISend to chosen destinations; skips our own), `Engine/NoteRouter.swift` (ALL plate
  and auto-strum notes: engine track per part unless internal sound off, + MIDI on the
  part's channel; tracks sent notes, releases them on off/channel change/PANIC).
  AutoStrummer now takes the router. MIDI chip (lit when on) → `Views/MIDIOutView.swift`.
  Next: tempo sync (MIDI clock in, Link).
- 2026-11-21: build 2 bumped and pushed; app icon added (FWD's icon with straight
  lines; `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` was missing) — committed, push
  waiting for Graham. Then: own sound per part (MIDIOutSettings plate/autoInternalSound;
  old `internalSound` read for both); Pentatonic/Blues follow the held chord (major or
  minor form by its 3rd; sus4 minor; no chord = key, major) via
  PlateScale.pitchClasses(in:chord:); auto-strum arpeggios coloured by the scale
  (AutoStrum.colouredFigure: one passing note just below each next chord note); STRINGS
  (10/13/16/20/24, HarpSetup.plateStrings; old plateOctaves read as 3n+1) replaces RANGE.

- 2026-11-21: rhythm section. `Models/Rhythm.swift` (9 styles: Rock/Pop, Country/Folk,
  Ballad, Waltz 3/4, Bossa, Reggae, Blues Shuffle (triplet grid, swings), Disco, R&B; each
  A/B, fill, intro, written one character per step; bass marks R 5 L O 3 6 7 over the
  chord, root E1–D♯2). `Engine/Conductor.swift` replaces AutoStrummer: one clock, 12
  ticks/beat, due-based; auto-strum locks to the rhythm's grid while it runs. FILL to bar
  end (next bar if in its last quarter), crash after fill/intro; style/A-B change at the
  bar. SYNC arms start on first pad (AUTO on) or first strum (off). Parts .drums (…A3,
  GM kit, ch 10) and .bass (…A4, GM 33, ch 3) with mixer strips and MIDI rows. Style,
  variation, intro saved. Rhythm row (`RhythmControls`) under the AUTO row.
- 2026-11-22: mixer at FWD's exact sizes (104 strips, dividers, fader 180, knob 52;
  instruments under M; scrolls both ways). Auto-strum colour via
  PlateScale.autoStrumColour: Blues = real blues scale on the chord root, Pentatonic
  chord-following, Major/Natural Minor = key notes, Chord/Chromatic none. STOP removed
  from the auto row; with HOLD on the kept chord ends when the rhythm stops. INTRO is a
  one-shot (not saved), goes off once played; while running the button is OUTRO
  (RhythmStyle.outro bar from the next bar line, then crash+kick+bass root, stop after
  2 beats). Top bar: AUTO instrument left (choosing one gives auto its own sound),
  app buttons middle, plate instrument right; plate controls: a 2-row Grid,
  KEY / order / RING over scale ("Chord") / STRINGS / OCT, fixedSize, trailing-aligned to the
  300-wide plate (may be wider than it).
- 2026-11-22: MIDI clock in + MIDI Learn (from FWD). `Models/MIDIControl.swift` (FWD's
  links/templates/pickup/scaling with harp targets: pads (press+release), hold, auto,
  tempo, tap, octave, rhythm start/stop/stop/sync/fill/intro-outro/A/B/styles, panic,
  per-part volume/pan/mute/FX, master; built-in nanoKONTROL2: strips 1–4 = plate, auto,
  drums, bass; fader 8 master, knob 8 tempo; ▶ start/stop, ■ stop, ● fill, cycle hold;
  MIDIClockTempo). `Store/MIDIControlCenter.swift` (cut-down FWD centre; MIDIInputGate on
  the MIDI thread decides keys → plate vs links; MIDIClockSettings in UserDefaults:
  follow, source, transport). MIDIInputManager passes 0xF8/FA/FB/FC with timestamps.
  Conductor: every 2nd pulse (24 ppq) is a tick while following; own timing takes over
  0.3 s after pulses stop; Start → next pulse is beat 1, starts drums if transport on;
  things started while following align to the clock's eighth/beat. Views: MIDILearnable
  (overlays, banner; Learn is switched on only from the MIDI menu's Learn button), MIDISettingsView (was MIDIOutView: controllers,
  templates, clock in, MIDI out). BPM shows the clock's tempo + CLOCK chip while
  following. Top bar: no AUTO label; ⓘ at far right. Untested on a device yet.
- 2026-11-23: code review for CPU. Rhythm bars compiled once per style
  (CompiledRhythmStyle; the conductor looks steps up); AutoStrum.cycle worked out on
  chord/pattern change (Conductor.autoCycle); HarpPlayer.plateNotes cached on its
  inputs; lit strings (PlateLights) and beat (BeatClock) are separate small
  ObservableObjects — keep high-rate state OUT of HarpPlayer's @Published, since
  every view watches it; meters measured only while the mixer is open
  (engine.metersShown); MIDI activity at most 10/s; Learn strip observes the centre
  only while on. Removed unused: AutoStrum.stepInterval, PlateScale.followsChord,
  engine currentStatus/quietTelemetry/telemetrySuppressed/ensureRunning/hasInstrument.
  Build has no warnings.
- 2026-11-23: scales reworked after Graham found some "off" (research: arranger
  keyboards' per-part chord rules, chord harps' chord-only plate, avoid notes).
  MajorKey → `MusicKey` (tonic + isMinor; HarpSetup.keyMinor). Minor pads: iv i V
  (V major) / VI III VII (ChordPad.chord(in:), degreeLabel(in:)). PlateScale: chord,
  major ("Melody"), pentatonic, minorPentatonic, blues — all follow the chord via
  `fitted` (drop notes a semitone above a chord tone, or below a chord tone the key
  lacks; sus4 drops the 3rd); naturalMinor and chromatic removed (decode → chord).
  Scale plates start on the first chord tone ≥ the plate's bottom. Auto-strum colour
  only for the pentatonics (AutoStrum.coloured, even-length rounds); Bass + Chord in
  3/4 = oom-pah-pah (cycle(beatsPerBar:), from the chosen style). AutoStrumPattern
  .style (default for new setups): RhythmBar.harp lines (. - c C u R 5 1–4, HarpMark)
  per style A/B/intro/outro, played by Conductor.playStyleAutoLocked on the style's
  grid, with or without drums; outro's final hit includes the chord. 16 styles: +swing,
  slowRock (12/8, triplets), march, funk, hipHop, samba, tango.
- 2026-11-23: plate slide + retune. Finger tracking moved into HarpPlayer
  (touchBegan/Moved/Ended, PlateTouch: string, note, loudness, anchor). Sideways slide
  sends CC11 expression on the plate (NoteRouter.controller → engine + MIDI out):
  110 at touch-down, ±120 × slide across the plate, 30–127; back to 110 1.5 s after the
  last finger lifts; PANIC sends 127. Note: auto-strum without its own sound shares
  the plate's instrument, so the slide moves it too. syncAutoStrum also calls
  retuneHeldStrings: held strings re-strike their note in the new chord.
- 2026-11-23: KEY menu lists the 12 keys of the current mode; MAJ / MIN chips
  (KeyModeToggle) beside KEY in the same grid cell (a row of its own made the plate shorter), keeping the tonic.
- 2026-11-23: plate slide reworked (Graham couldn't hear expression: ±12/127 for a small
  wobble was inaudible on a fading harp). PlateSlide (expression, modWheel, pitchBend,
  aftertouch, off) × SlideDepth (subtle/medium/strong spans), HarpSetup.plateSlide /
  slideDepth, chosen in the MIDI menu's Strum Plate Slide section.
  NoteRouter.performance(status:data1:data2:) for CC / bend / pressure. Resets to resting
  1 s after the last lift; switching resets the old control; PANIC resets all.
- 2026-11-24: portrait. FWD's `Views/FlowLayout.swift` copied. Top bar: ViewThatFits
  (one line, else instruments row + app buttons row). AutoStrumBar and RhythmControls
  are FlowLayouts (wrap). Main area in a GeometryReader: narrower than
  ContentView.narrowWidth (1000) the plate controls wrap to 300 wide (FlowLayout)
  instead of the 2-row Grid. Landscape unchanged.
- 2026-11-24: help mode from FWD (`Views/HelpMode.swift`, without FWD's menu pages;
  `Views/HelpTopics.swift` written for the harp). ? (HelpButton) on the top bar before ⓘ;
  `.helpHost()` on ContentView; `.helpTag(topic, instance:)` on every control (after
  `.midiLearnable`, outside any `.disabled`), per-pad overlays in PadsView, mixer strips
  by part. Help and Learn switch each other off. When a control changes, change its
  text in HelpTopics.
- PARKED (2026-11-24): named songs in a set list for one-touch recall. Explored with
  Graham: a song = full HarpSetup snapshot (sounds, patches, FX, mix, key, scale, plate,
  auto, tempo, style); controller links/clock/MIDI out stay app-wide; recall from tiles
  (in place of the pads), top-bar ◀ name ▶, MIDI Learn next/previous; edits kept but
  only written on Save (dot shows unsaved); same instruments switch at once (at the bar
  line with drums), different plugins stop the band and load behind the overlay.
  FWD's SongStore.open / SongPersistence library is the model. Open questions: one or
  several set lists; song tempo vs followed clock; bar-line switching wanted?
- 2026-11-25: after an unrepeatable hang while strumming: NoteRouter sends everything
  from its own serial queue (com.fwdharp.notes) and returns at once, so the main thread
  and the conductor (which calls it with its lock held) never wait on an instrument.
  Engine all-notes-off and PANIC go through router.afterQueued, after earlier notes.
  Audition keys (editor, built-in sheet) still call the engine directly. If a hang
  recurs: iPad Settings ▸ Privacy & Security ▸ Analytics Data, FWDHarp-*.ips.
- 2026-11-25: `.defersSystemGestures(on: .all)` on ContentView (edge swipes play first).
  Four/five-finger swipes and pinch are iPadOS's: off only in Settings ▸ Multitasking &
  Gestures (and iPadOS 26–27.2 still swallows them even then: Apple bug FB24795986);
  Guided Access blocks them all for a performance.
- 2026-11-25: Chromatic back in SCALE (all 12 notes, starts on the key's note and does
  NOT follow the chord or move with it: for melodies, clashes accepted). Plate order
  Custom: HarpSetup.customPlateFigure (steps 1 3 5 7 8, 1–8 long, default 1 3 5,
  PlatePattern.normalized), counted from the chord's root (StrumPlate.rootIndex), each
  round a chord-size higher; 7 = the octave on triads. Edited in
  `Views/CustomFigureView.swift` ("Edit Custom…" in the order menu; editing also selects
  Custom). On scale plates Custom plays Straight.
  Inversions (same day): the first step is the figure's lowest note, steps below it go
  up an octave (5 1 3 = G C E, 3 5 1 = E G C), each round starting as low as it can.
  A sweep no longer restrikes a note the finger is already sounding (Custom can put
  the same note on neighbouring strings; the cut-and-restrike clicked).
  Plate centring (same day): StrumPlate.plate(...) builds the whole plate (HarpPlayer
  calls it). Its bottom drops whole octaves from the usual key-note-in-octave-3 until
  every string has a note and its middle is within an octave of a 3-octave plate's
  (decided on the key's tonic chord, so no jump on chord changes). 10/13/16 chord
  strings and the scales stay put; 20/24 move down. A figure too sparse to fill even
  then: StrumPlateView shows only the strings it can fill. Auto-strum's notes unchanged.
