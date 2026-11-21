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
- Version 1.0, build 1. Every TestFlight upload needs `CURRENT_PROJECT_VERSION`
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

