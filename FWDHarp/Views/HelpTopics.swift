import Foundation

/// Every piece of help text in FWD Harp, in one place so it can be read through and
/// corrected together. Shown by help mode (HelpMode.swift) when a control is tapped,
/// and read out by VoiceOver as each control's hint. Written 2026-11-24, after FWD
/// Sequencer's HelpTopics.
///
/// Style: say what the control does, then any gesture that isn't obvious. Plain words,
/// one to three short sentences. If a control's behaviour changes, change its text here.
enum HelpTopic: String {
    // Top bar
    case autoInstrument, plateInstrument, effects, mixerButton, midiButton, panic, cpu, about

    // Auto-strum row
    case autoStrum, hold, autoPattern, tempo, tapTempo, clockTempo

    // Rhythm row
    case rhythmStart, rhythmSync, rhythmStyle, rhythmVariation, intro, outro, fill, beatLights

    // Pads
    case chordPad, seventhPad, susPad

    // Above the plate, and the plate
    case key, keyMode, plateOrder, ring, scale, strings, octave, strumPlate

    // Mixer
    case mixerMaster, mixerFader, mixerPan, mixerMute, mixerSolo, mixerEffects, mixerOwnSound,
         mixerInstrument, mixerDone, liveMix, autoOctave

    var title: String {
        switch self {
        case .autoInstrument: return "Auto-Strum Instrument"
        case .plateInstrument: return "Plate Instrument"
        case .effects: return "Effects (FX)"
        case .mixerButton: return "Mixer"
        case .midiButton: return "MIDI"
        case .panic: return "Panic"
        case .cpu: return "CPU"
        case .about: return "About and Credits"

        case .autoStrum: return "Auto-Strum"
        case .hold: return "Hold"
        case .autoPattern: return "Auto-Strum Pattern"
        case .tempo: return "Tempo"
        case .tapTempo: return "Tap Tempo"
        case .clockTempo: return "Following MIDI Clock"

        case .rhythmStart: return "Start / Stop"
        case .rhythmSync: return "Sync"
        case .rhythmStyle: return "Rhythm Style"
        case .rhythmVariation: return "Variation A / B"
        case .intro: return "Intro"
        case .outro: return "Outro"
        case .fill: return "Fill"
        case .beatLights: return "Beat Lights"

        case .chordPad: return "Chord Pad"
        case .seventhPad: return "7th"
        case .susPad: return "sus2 / sus4"

        case .key: return "Key"
        case .keyMode: return "Major / Minor"
        case .plateOrder: return "Plate Order"
        case .ring: return "Ring"
        case .scale: return "Scale"
        case .strings: return "Strings"
        case .octave: return "Octave"
        case .strumPlate: return "Strum Plate"

        case .mixerMaster: return "Master"
        case .mixerFader: return "Volume"
        case .mixerPan: return "Pan"
        case .mixerMute: return "Mute"
        case .mixerSolo: return "Solo"
        case .liveMix: return "Live Mix"
        case .autoOctave: return "Auto-Strum Octave"
        case .mixerEffects: return "Effects"
        case .mixerOwnSound: return "Own Sound"
        case .mixerInstrument: return "Instrument"
        case .mixerDone: return "Done"
        }
    }

    var text: String {
        switch self {
        case .autoInstrument:
            return "The instrument auto-strum plays. Until you choose one it plays the plate's; choosing one here gives auto-strum its own. EDIT opens the instrument's own screen."
        case .plateInstrument:
            return "The instrument the strum plate plays: one of your AUv3 instruments, or a built-in sound. EDIT opens its own screen, where its sound can be changed; that sound is kept."
        case .effects:
            return "Tap to switch this instrument's effects on or off. Long press to add, change, reorder or remove them."
        case .mixerButton:
            return "Shows the mixer in place of the pads, so the plate can still be played while you set the levels. Tap again, or Done, for the pads."
        case .midiButton:
            return "MIDI settings: start MIDI Learn, what the plate's slide sends, your controllers and their templates, following a MIDI clock, and MIDI out to other apps and hardware. Lit while MIDI out is on or a clock is followed."
        case .panic:
            return "Stops every note at once, here and on MIDI out: for a note that hangs. Auto-strum and the drums stop too."
        case .cpu:
            return "How hard the iPad is working on sound. If it gets near 100% the sound may crackle: try fewer effects or a lighter instrument."
        case .about:
            return "Version, credits and the licences for the built-in sounds."

        case .autoStrum:
            return "With AUTO lit, pressing a chord pad plays the pattern for you, in time. Without it, the pads only choose the chord and the plate makes the sound."
        case .hold:
            return "Keeps the last chord after you lift your hand, so auto-strum (or the plate) carries on with it until another pad is pressed. Tap a kept 7th or sus again to take it off. Turning HOLD off lets the chord go; with HOLD on it also ends when the drums stop."
        case .autoPattern:
            return "What auto-strum plays. Style plays the rhythm style's own harp part; the others are arpeggios up, down and up-and-down (over one or two octaves), block chords, bass and chord, or a single sweep each time a pad is pressed."
        case .tempo:
            return "Beats per minute, for auto-strum and the drums together. Drag up or down to change it; double tap for the default."
        case .tapTempo:
            return "Tap it in time, four or so taps, to set the tempo."
        case .clockTempo:
            return "The tempo comes from the MIDI clock being followed (MIDI ▸ Clock In), so it can't be changed here. Lit once the clock arrives."

        case .rhythmStart:
            return "Starts and stops the drums and bass. With INTRO lit they begin with the style's intro."
        case .rhythmSync:
            return "Waits, and starts the drums with your first chord pad (with AUTO on) or your first strum (with it off)."
        case .rhythmStyle:
            return "The drum and bass style, each with its own harp part for auto-strum's Style pattern. Changed while playing, it switches at the next bar."
        case .rhythmVariation:
            return "Two versions of each style: A, and a busier B. Switches at the next bar."
        case .intro:
            return "Lit before you start: the drums begin with the style's one-bar intro. It goes off once it has played, and the button becomes OUTRO."
        case .outro:
            return "Plays the style's ending from the next bar, with a final hit, then the drums stop."
        case .fill:
            return "A drum fill to the end of the bar (or through the next one, pressed near the end), then the style carries on with a crash."
        case .beatLights:
            return "One light for each beat of the bar, following the drums. Orange during an intro, fill or outro."

        case .chordPad:
            return "Press to choose the chord, named in the key. The top row is the key's main chords, the bottom row their relatives. Pressing another pad changes chord; strings you hold on the plate change with it."
        case .seventhPad:
            return "Hold with a chord pad to add the 7th: a dominant 7th on major chords (G7), a minor 7th on minor ones (Am7)."
        case .susPad:
            return "Hold with a chord pad to replace the 3rd with the 2nd or the 4th (Csus2, Csus4). With the 7th too: 7sus2, 7sus4."

        case .key:
            return "The key the pads play in. MAJ and MIN beside it choose a major or minor key."
        case .keyMode:
            return "A major or minor key, on the same key note (C or Cm). In a minor key the top pads are iv i V, the 5 major as song books play it."
        case .plateOrder:
            return "The order of notes up the plate: straight, alternating, rolling, octaves, bass and chord, or Custom — your own figure of chord notes (1 3 5 to start; 5 1 3 for an inversion), set with Edit Custom…. A swipe then plays that figure."
        case .ring:
            return "How long a plate note sounds: While Held (until your finger leaves the string), short, medium or long, or until the chord changes."
        case .scale:
            return "What the plate offers. Chord: only the chord's notes. Melody, Pentatonic, Minor Pentatonic and Blues add notes for tunes, always ones that fit the chord held, so nothing sounds wrong. Chromatic has every note, for playing melodies note by note; it does not follow the chord, so some notes will clash."
        case .strings:
            return "How many strings the plate has, in the same height: 10 for three octaves of a chord, more for a finer, wider plate."
        case .octave:
            return "Moves the whole plate down or up an octave, two at most. Auto-strum has its own OCT, in its row."
        case .strumPlate:
            return "Touch a string to pluck it, or swipe across to strum; low at the bottom. Further right plays louder. Slide a held finger sideways to swell, soften or bend it (MIDI ▸ Strum Plate Slide)."

        case .mixerMaster:
            return "Everything together: the level of the whole harp."
        case .mixerFader:
            return "This part's level. Double tap for 0 dB."
        case .mixerPan:
            return "Places this part left or right. Double tap for the centre."
        case .mixerMute:
            return "Silences this part, here and over MIDI out; it keeps playing, unheard."
        case .mixerSolo:
            return "Hear only the soloed parts: every part not soloed goes silent, here and over MIDI out. Solo several to hear them together. Not kept when the app closes."
        case .liveMix:
            return "Each part's level, mute and solo, to reach while playing. The same settings as the mixer: a change here shows there."
        case .autoOctave:
            return "Moves auto-strum's patterns down or up an octave, two at most. The plate has its own OCT."
        case .mixerEffects:
            return "Tap to switch this part's effects on or off. Long press to edit them."
        case .mixerOwnSound:
            return "Gives auto-strum an instrument of its own. Off, it plays through the plate's, on the plate's strip."
        case .mixerInstrument:
            return "The instrument this part plays. EDIT opens its own screen."
        case .mixerDone:
            return "Closes the mixer and brings the pads back."
        }
    }
}
