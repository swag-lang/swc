#global internal
#global namespace Viewers.Table

using Core, Gui

// Visible strings of the tabular-text viewer.
struct Texts
{
    ui_Column:          string = "Column %"
    ui_Details:         string = "% · % · %"
    ui_Row:             string = "1 row"
    ui_Rows:            string = "% rows"
    ui_OneColumn:       string = "1 column"
    ui_Columns:         string = "% columns"
    err_TooLarge:       string = "the tabular viewer accepts files up to 32 MiB"
    err_TooManyColumns: string = "the tabular viewer accepts up to 256 columns"
    err_UnclosedQuote:  string = "a quoted field reaches the end of the file"
}

private const FrenchStringsName = "lang/fr/scope.table.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.table.tweak")

private var g_Texts: Texts

// Returns the visible strings of the tabular-text viewer in the active language.
func texts()->const *Texts => &g_Texts

// Registers this viewer's string table with the application.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.table")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
