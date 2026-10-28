#global internal
#global namespace Viewers.Midi

using Core, Gui

// Visible strings of the MIDI viewer.
struct Texts
{
    ui_Track:            string = "Track"     // Option choosing which track the roll shows.
    ui_AllTracks:        string = "All tracks"
    ui_TrackName:        string = "Track %"
    ui_TrackChoice:      string = "% — %"
    ui_ZoomOut:          string = "Zoom Out"
    ui_ZoomIn:           string = "Zoom In"
    ui_Fit:              string = "Fit Complete Score"
    ui_ZoomMenu:         string = "Horizontal Zoom · Ctrl+wheel: pitch zoom · Page Up/Down: scroll"
    ui_PitchLabels:      string = "Pitch labels (C4 = MIDI 60)"
    ui_PitchScientific:  string = "C4 names"
    ui_PitchMidiNumber:  string = "MIDI numbers"
    ui_KeyboardWidth:    string = "Piano keyboard width"
    ui_KeyboardCompact:  string = "Compact"
    ui_KeyboardStandard: string = "Standard"
    ui_KeyboardWide:     string = "Wide"
    ui_PianoRoll:        string = "PIANO ROLL"
    ui_NoNotes:          string = "No note events"
    ui_OneTrack:         string = "1 track"
    ui_Tracks:           string = "% tracks"
    ui_OneNote:          string = "1 note"
    ui_Notes:            string = "% notes"
    ui_Summary:          string = "% · % · % · % BPM · % · %"
    ui_Details:          string = "% · % · % · %"     // Tracks, meter, notes and length, at the foot of the score.
    ui_Channel:          string = "channel %"         // The channel a track plays on, under its name.
    ui_Presentation:     string = "Presentation"      // Option choosing how the score is laid out.
    ui_ByTrack:          string = "Tracks"            // One lane per track.
    ui_ByPitch:          string = "Piano roll"        // One row per key.
    ui_Major:            string = "major"
    ui_Minor:            string = "minor"
    err_TooLarge:        string = "the MIDI viewer accepts files up to 32 MiB"
    err_TooManyNotes:    string = "the MIDI file contains too many notes to display safely"
    err_Header:          string = "the file does not contain a valid Standard MIDI header"
    err_Track:           string = "the MIDI track chain ends before its declared track count"
    err_Event:           string = "a MIDI event ends outside its track"
}

private const FrenchStringsName = "lang/fr/scope.midi.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.midi.tweak")

private var g_Texts: Texts

// Returns the visible strings of the MIDI viewer in the active language.
func texts()->const *Texts => &g_Texts

// Counts tracks and notes in the active language, singular for one.
func trackCountText(count: u64)->String => count == 1 ? String.from(texts().ui_OneTrack) : Format.toString(texts().ui_Tracks, count)
func noteCountText(count: u64)->String  => count == 1 ? String.from(texts().ui_OneNote) : Format.toString(texts().ui_Notes, count)

// Names one way of labelling the pitches.
func pitchLabelText(mode: PitchLabelMode)->string => mode == .MidiNumber ? texts().ui_PitchMidiNumber : texts().ui_PitchScientific

// Names one width of the piano keyboard.
func keyboardWidthText(index: u32)->string
{
    switch index
    {
    case 0:  return texts().ui_KeyboardCompact
    case 1:  return texts().ui_KeyboardStandard
    default: return texts().ui_KeyboardWide
    }
}

// Registers this viewer's string table with the application.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.midi")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
