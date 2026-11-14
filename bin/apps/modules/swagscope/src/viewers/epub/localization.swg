#global internal
#global namespace Viewers.Epub

using Core, Gui

// Visible strings of the EPUB reader.
struct Texts
{
    ui_Name:               string = "EPUB book"
    ui_Previous:           string = "Previous chapter"
    ui_Next:               string = "Next chapter"
    ui_Preparing:          string = "Preparing book…"
    ui_Details:            string = "EPUB · chapter % of %"
    err_Invalid:          string = "This EPUB book has a damaged structure."
    err_TooLarge:         string = "This EPUB book is too large to open safely."
    err_UnsupportedChapter: string = "This EPUB book has a chapter format that cannot be read."
    err_NoChapters:       string = "This EPUB book contains no readable chapters."
}

private const FrenchStringsName = "lang/fr/scope.epub.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.epub.tweak")

private var g_Texts: Texts

func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.epub")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
