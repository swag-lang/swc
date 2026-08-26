#global internal

using Core, Gui

struct MidiStrings
{
    ui_AllTracks:    string = "All tracks"
    ui_TrackName:    string = "Track %"
    ui_TrackChoice:  string = "% — % notes"
    ui_ZoomOut:      string = "Zoom out"
    ui_ZoomIn:       string = "Zoom in"
    ui_Fit:          string = "Fit complete score"
    ui_PianoRoll:    string = "PIANO ROLL"
    ui_NoNotes:      string = "No note events"
    ui_Summary:      string = "% tracks · % notes · % · % BPM · % · %"
    ui_Details:      string = "MIDI format % · % tracks · % notes · %"
    ui_Major:        string = "major"
    ui_Minor:        string = "minor"
    err_TooLarge:    string = "the MIDI viewer accepts files up to 32 MiB"
    err_TooManyNotes: string = "the MIDI file contains too many notes to display safely"
    err_Header:      string = "the file does not contain a valid Standard MIDI header"
    err_Track:       string = "the MIDI track chain ends before its declared track count"
    err_Event:       string = "a MIDI event ends outside its track"
}

private const FrenchStringsName = "lang/fr/filescope.midi.tweak"
private const FrenchStrings = #include("../../../datas/lang/fr/filescope.midi.tweak")

private var g_MidiStrings: MidiStrings

func midiStrings()->const *MidiStrings => &g_MidiStrings

func registerMidiStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'MidiStrings(&g_MidiStrings, "filescope.midi")
}

#run
{
    expect Gui.validateStrings'MidiStrings(cast(string) FrenchStrings)
}
