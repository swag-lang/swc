#global internal
#global namespace Viewers.Captions

using Core, Gui

// Visible strings of the subtitle document viewer.
struct Texts
{
    ui_OneCue:           string = "1 cue"                                  // Count of one subtitle cue.
    ui_Cues:             string = "% cues"                                 // Count of several subtitle cues.
    ui_CuePosition:      string = "Cue % / %"                              // Current cue number and total, at the foot of the list.
    ui_GoToCue:          string = "Go to Cue"                              // Title of cue navigation.
    ui_PreviousCue:      string = "Previous Cue"                           // Command moving to the cue before the current one.
    ui_NextCue:          string = "Next Cue"                               // Command moving to the cue after the current one.
    ui_FirstCue:         string = "First Cue"                              // Command moving to the first cue.
    ui_LastCue:          string = "Last Cue"                               // Command moving to the last cue.
    ui_CueRange:         string = "Enter a cue number from 1 to %."        // Explanation above the cue input.
    ui_GoToTime:         string = "Go to Time"                             // Title and tooltip of time navigation.
    ui_TimeRange:        string = "Enter seconds, MM:SS, or HH:MM:SS."     // Explanation above the time input.
}

private const FrenchStringsName = "lang/fr/scope.subtitle.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.subtitle.tweak")

private var g_Texts: Texts

// Returns the visible strings of the subtitle viewer in the active language.
func texts()->const *Texts => &g_Texts

// Registers this viewer's string table with the application.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.subtitle")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
