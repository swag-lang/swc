#global internal

using Core, Gui

// Visible strings of the subtitle document viewer.
struct SubtitleStrings
{
    ui_Details: string = "% · % · %"     // Format, cue count, and duration shown in the host summary.
    ui_OneCue:  string = "1 cue"         // Count of one subtitle cue.
    ui_Cues:    string = "% cues"        // Count of several subtitle cues.
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
