#global internal
#global namespace Viewers.Pptx

using Core, Gui

struct Texts
{
    ui_Name:         string = "Presentation"
    ui_Preparing:    string = "Preparing presentation…"
    ui_Details:      string = "Presentation · % slides · % images not shown"
    ui_Slide:        string = "Slide %"
    ui_ImageOmitted: string = "[Image not shown]"
    err_Invalid:     string = "This presentation has a damaged structure."
    err_TooLarge:    string = "This presentation is too large to open safely."
}

private const FrenchStringsName = "lang/fr/scope.pptx.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.pptx.tweak")

private var g_Texts: Texts

func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.pptx")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
