#global internal
#global namespace Viewers.Comic

using Core, Gui

// Visible strings of the comic-book reader.
struct Texts
{
    ui_Name:      string = "Comic book"
    ui_Previous:  string = "Previous page"
    ui_Next:      string = "Next page"
    ui_Preparing: string = "Preparing page…"
    ui_Details:   string = "Comic book · page % of %"
    err_NoPages:  string = "This comic book contains no readable pages."
}

private const FrenchStringsName = "lang/fr/scope.comic.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.comic.tweak")

private var g_Texts: Texts

func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.comic")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
