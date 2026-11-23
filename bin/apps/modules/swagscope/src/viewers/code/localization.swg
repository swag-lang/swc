#global internal
#global namespace Viewers.Code

using Core, Gui

// Visible strings of the source viewer.
//
// A language is named by its own name — `Swag`, `C++`, `Python` — and an encoding by its
// standard spelling, so the summary below is the only sentence this viewer writes.
struct Texts
{
    ui_ZoomMenu:             string = "Zoom…"                      // Tooltip of the zoom value menu.
    ui_HighlightAs:          string = "Highlight as %"             // Lens command coloring the source as the language it names.
    ui_PlainText:            string = "Plain Text"                 // Language choice showing the source without syntax colors.
    ui_Wrap:                 string = "Wrap Long Lines"            // Lens command folding long source lines into the view.
    ui_Numbers:              string = "Line Numbers"               // Lens command showing logical line numbers in a gutter.
    ui_Blanks:               string = "Show Whitespace"            // Lens command marking each space with a dot and each tabulation with an arrow.
    ui_MatchingDelimiter:    string = "Go to Matching Bracket"     // Lens command moving the caret to the bracket, parenthesis or brace pairing with the one at it.
    ui_DelimiterUnavailable: string = "% · no matching delimiter in loaded source"
    ui_TabWidth:             string = "Tab Width"     // Lens commands placing a tab stop every 2, 4 or 8 spaces; the number follows.
    // Summary the host shows beside the file size. `%` takes the name of the language.
    ui_Details:           string = "% · UTF-8"
    ui_Detection:         string = "% · % · detected from %"
    ui_ManualDetails:     string = "% · % · manual language choice"
    ui_ExtensionEvidence: string = "extension %"
    ui_FilenameEvidence:  string = "filename %"
    ui_ShebangEvidence:   string = "interpreter line"
    ui_DefaultEvidence:   string = "default C"
    err_Read:             string = "source stream could not be read"     // Diagnostics of a source the viewer cannot show.
    err_ZeroByte:         string = "source contains a zero byte and is not supported UTF-8 text"
}

private const FrenchStringsName = "lang/fr/scope.code.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.code.tweak")

private var g_Texts: Texts

// Returns the visible strings of the source viewer in the active language.
func texts()->const *Texts => &g_Texts

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.code")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
