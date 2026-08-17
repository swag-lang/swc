#global public

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
private const FrenchStrings = #include("../datas/lang/fr/filescope.code.tweak")

private var g_CodeStrings: CodeStrings

// Returns the visible strings of the source viewer in the active language.
func codeStrings()->const *CodeStrings => &g_CodeStrings

// Registers this plugin's string table with the host that loaded it.
//
// A plugin enters the process long after the host chose a language, so its translations are
// published into the host's bundle before the table is registered: [[Gui.registerStrings]] then
// finds them and the viewer opens in the language of the window around it. Calling this again
// is a no-op, so the first view of this format pays for it and no other does.
func registerCodeStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'CodeStrings(&g_CodeStrings, "filescope.code")
}

#run
{
    expect Gui.validateStrings'CodeStrings(cast(string) FrenchStrings)
}
