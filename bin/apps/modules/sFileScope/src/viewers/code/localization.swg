#global internal

using Core, Gui

// Visible strings of the source viewer.
//
// A language is named by its own name — `Swag`, `C++`, `Python` — and an encoding by its
// standard spelling, so the summary below is the only sentence this viewer writes.
struct CodeStrings
{
    // Summary the host shows beside the file size. `%` takes the name of the language.
    ui_Details: string = "% · UTF-8 · streamed"
}

private const FrenchStringsName = "lang/fr/filescope.code.tweak"
private const FrenchStrings = #include("../../../datas/lang/fr/filescope.code.tweak")

private var g_CodeStrings: CodeStrings

// Returns the visible strings of the source viewer in the active language.
func codeStrings()->const *CodeStrings => &g_CodeStrings

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerCodeStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'CodeStrings(&g_CodeStrings, "filescope.code")
}

#run
{
    expect Gui.validateStrings'CodeStrings(cast(string) FrenchStrings)
}
