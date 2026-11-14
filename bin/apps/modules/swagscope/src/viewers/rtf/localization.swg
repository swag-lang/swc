#global internal
#global namespace Viewers.Rtf

using Core, Gui

// Visible strings of the Rich Text Format reader.
struct Texts
{
    ui_Name:          string = "Rich text document"
    ui_Preparing:     string = "Preparing document…"
    ui_Details:       string = "Rich text document · % paragraphs · % images or objects not shown"
    ui_ImageOmitted:  string = "[Image not shown]"
    ui_ObjectOmitted: string = "[Embedded object not shown]"
    err_Invalid:     string = "This rich text document has a damaged structure."
    err_TooLarge:    string = "This rich text document is too large to open safely."
    err_CodePage:    string = "This rich text document uses an unsupported code page."
}

private const FrenchStringsName = "lang/fr/scope.rtf.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.rtf.tweak")

private var g_Texts: Texts

func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.rtf")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
