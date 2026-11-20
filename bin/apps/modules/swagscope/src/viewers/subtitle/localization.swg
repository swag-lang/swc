#global internal
#global namespace Viewers.Captions

using Core, Gui

// Visible strings of the subtitle document viewer.
struct Texts
{
    ui_OneCue:        string = "1 cue"                                  // Count of one subtitle cue.
    ui_Cues:          string = "% cues"                                 // Count of several subtitle cues.
    ui_CuePosition:   string = "Cue % / %"                              // Current cue number and total, at the foot of the list.
    ui_GoToCue:       string = "Go to Cue"                              // Title of cue navigation.
    ui_GoToCueNumber: string = "Go to Cue %"                            // Lens row going to the cue numbered after a colon.
    ui_CopyCue:       string = "Copy Cue"                               // Puts the words of the current cue on the clipboard.
    ui_CopySelectedCues: string = "Copy Selected Cues"                  // Copies the selected contiguous range with cue numbers and times.
    ui_SelectCuesHint: string = "Shift-click or Shift+Up/Down selects a cue range; Ctrl+Shift+C copies it."
    ui_CopyDialogue:  string = "Copy Dialogue"                          // Puts the words of every cue, without their times, on the clipboard.
    ui_CopyNormalized: string = "Copy Normalized Transcript…"
    ui_ExportNormalized: string = "Export Normalized Transcript…"
    ui_NormalizationTitle: string = "Normalize Subtitle Transcript"
    ui_NormalizationLoss: string = "The % source becomes % decoded cues in SubRip; parser-discarded malformed or empty cue records: %. This reader keeps cue times and plain text only; source identifiers, styling, positioning, and markup are not preserved."
    ui_NormalizationQuestion: string = "Continue with this normalized transcript?"
    ui_NormalizationFile: string = "SubRip Subtitles"
    ui_ExportTooLarge: string = "The normalized transcript exceeds the 64 MiB export limit."
    ui_PreviousCue:   string = "Previous Cue"                           // Command moving to the cue before the current one.
    ui_NextCue:       string = "Next Cue"                               // Command moving to the cue after the current one.
    ui_FirstCue:      string = "First Cue"                              // Command moving to the first cue.
    ui_LastCue:       string = "Last Cue"                               // Command moving to the last cue.
    ui_CueRange:      string = "Enter a cue number from 1 to %."        // Explanation above the cue input.
    ui_GoToTime:      string = "Go to Time"                             // Title and tooltip of time navigation.
    ui_TimeRange:     string = "Enter seconds, MM:SS, or HH:MM:SS."     // Explanation above the time input.
    ui_FilterDuration: string = "Filter by Minimum Cue Duration"       // Lens action that hides shorter cues.
    ui_ClearDurationFilter: string = "Show All Cues"                   // Restores cues hidden by the duration filter.
    ui_FilterDurationHint: string = "Enter a minimum in seconds; enter 0 to show all cues. Search still covers every cue."
    ui_FilterMarker: string = "Cues ≥ %{f2} s"                         // Marker shown in the reading header while filtering.
    ui_OverlapMarkerHint: string = "Colored ruler bands group overlapping cues. Click the ruler to navigate."
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
