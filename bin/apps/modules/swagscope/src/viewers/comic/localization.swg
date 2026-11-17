#global internal
#global namespace Viewers.Comic

using Core, Gui

// Visible strings of the comic-book reader.
struct Texts
{
    ui_Name:        string = "Comic book"
    ui_Previous:    string = "Previous Page"
    ui_Next:        string = "Next Page"
    ui_RightToLeft: string = "Read Right to Left"
    ui_Preparing:   string = "Preparing page…"
    ui_Details:     string = "Comic book · page % of %"
    ui_OnePage:     string = "1 page"      // Length of a one-page book.
    ui_Pages:       string = "% pages"     // Length of a longer book.
    ui_GoToPage:    string = "Go to Page"
    ui_PageRange:   string = "Enter a page number from 1 to %."
    err_NoPages:    string = "This comic book contains no readable pages."
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
