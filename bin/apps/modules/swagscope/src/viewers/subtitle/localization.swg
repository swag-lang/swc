#global internal

using Core, Gui

// Visible strings of the subtitle document viewer.
struct SubtitleStrings
{
    ui_OneCue:    string = "1 cue"                                  // Count of one subtitle cue.
    ui_Cues:      string = "% cues"                                 // Count of several subtitle cues.
    ui_GoToCue:   string = "Go to cue"                              // Title and tooltip of cue navigation.
    ui_CueRange:  string = "Enter a cue number from 1 to %."        // Explanation above the cue input.
    ui_GoToTime:  string = "Go to time"                             // Title and tooltip of time navigation.
    ui_TimeRange: string = "Enter seconds, MM:SS, or HH:MM:SS."     // Explanation above the time input.
}

private const FrenchStringsName = "lang/fr/scope.subtitle.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.subtitle.tweak")

private var g_SubtitleStrings: SubtitleStrings

// Returns the visible strings of the subtitle viewer in the active language.
func subtitleStrings()->const *SubtitleStrings => &g_SubtitleStrings

// Registers this viewer's string table with the application.
func registerSubtitleStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'SubtitleStrings(&g_SubtitleStrings, "scope.subtitle")
}

#run
{
    expect Gui.validateStrings'SubtitleStrings(cast(string) FrenchStrings)
}
