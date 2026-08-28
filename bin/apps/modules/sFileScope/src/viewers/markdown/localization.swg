#global internal

using Core, Gui

// Visible strings of the Markdown viewer.
//
// The appearance names are the names the styles are known by — `GitHub`, `Pixyll` — so they are
// proper names rather than sentences, and only `Application` names something this program owns.
struct MarkdownStrings
{
    ui_TipWidth: string = "Reading width"                   // Tooltip of the reading-measure selector.
    ui_Narrow:   string = "Narrow"                          // Narrowest reading measure.
    ui_Medium:   string = "Medium"                          // Default reading measure.
    ui_Wide:     string = "Wide"                            // Widest fixed reading measure.
    ui_Fluid:    string = "Fluid"                           // Reading measure following the window.
    ui_TipTheme: string = "Markdown appearance"             // Tooltip of the appearance selector.
    ui_ThemeApp: string = "Application"                     // Appearance following the application palette.
    ui_Details:  string = "Markdown · UTF-8 · streamed"     // Summary the host shows beside the file size.
}

private const FrenchStringsName = "lang/fr/filescope.markdown.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/filescope.markdown.tweak")

private var g_MarkdownStrings: MarkdownStrings

// Returns the visible strings of the Markdown viewer in the active language.
func markdownStrings()->const *MarkdownStrings => &g_MarkdownStrings

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerMarkdownStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'MarkdownStrings(&g_MarkdownStrings, "filescope.markdown")
}

#run
{
    expect Gui.validateStrings'MarkdownStrings(cast(string) FrenchStrings)
}
