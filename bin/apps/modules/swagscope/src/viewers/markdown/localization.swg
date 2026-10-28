#global internal
#global namespace Viewers.MarkdownText

using Core, Gui

// Visible strings of the Markdown viewer.
//
// The appearance names are the names the styles are known by — `GitHub`, `Pixyll` — so they are
// proper names rather than sentences, and only `Application` names something this program owns.
struct Texts
{
    ui_Width:        string = "Reading width"             // Option choosing the reading measure.
    ui_Narrow:       string = "Narrow"                    // Narrowest reading measure.
    ui_Medium:       string = "Medium"                    // Default reading measure.
    ui_Wide:         string = "Wide"                      // Widest fixed reading measure.
    ui_Fluid:        string = "Fluid"                     // Reading measure following the window.
    ui_Theme:        string = "Appearance"                // Option choosing how the document is styled.
    ui_ZoomMenu:     string = "Markdown Zoom Options"     // Tooltip of the zoom value menu.
    ui_ThemeApp:     string = "Application"               // Appearance following the application palette.
    ui_OneLine:      string = "1 line"                    // Singular source line count.
    ui_Lines:        string = "% lines"                   // Plural source line count.
    ui_OneWord:      string = "1 word"                    // Singular whitespace-delimited word count.
    ui_Words:        string = "% words"                   // Plural whitespace-delimited word count.
    ui_OneCharacter: string = "1 character"               // Singular Unicode character count.
    ui_Characters:   string = "% characters"              // Plural Unicode character count.
    ui_Details:      string = "Markdown · UTF-8"          // Summary the host shows beside the file size.
}

private const FrenchStringsName = "lang/fr/scope.markdown.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.markdown.tweak")

private var g_Texts: Texts

// Returns the visible strings of the Markdown viewer in the active language.
func texts()->const *Texts => &g_Texts

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.markdown")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
