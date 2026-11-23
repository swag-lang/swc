#global internal
#global namespace Viewers.Odt

using Core, Gui

struct Texts
{
    ui_Name:             string = "OpenDocument Text"
    ui_Preparing:        string = "Preparing document…"
    ui_Details:          string = "OpenDocument · % paragraphs"
    ui_OneParagraph:     string = "OpenDocument · 1 paragraph"
    ui_Tables:           string = " · % tables"
    ui_OneTable:         string = " · 1 table"
    ui_Images:           string = " · % images"
    ui_OneImage:         string = " · 1 image"
    ui_Omitted:          string = " · % items not shown"
    ui_OneOmitted:       string = " · 1 item not shown"
    ui_LayoutSimplified: string = " · some layout simplified"
    ui_ImageDescription: string = "Embedded image"
    ui_ImageOmitted:     string = "[Image not shown]"
    ui_ObjectOmitted:    string = "[Embedded content not shown]"
    ui_Footnote:         string = "Footnote"
    ui_Comment:          string = "Comment"
    err_Invalid:         string = "This OpenDocument file has a damaged structure."
    err_TooLarge:        string = "This document is too large to open safely."
    err_Encrypted:       string = "This document is password-protected."
}

private const FrenchStringsName = "lang/fr/scope.odt.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.odt.tweak")
private var g_Texts: Texts
func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.odt")
}

#run { expect Gui.validateStrings'Texts(cast(string, FrenchStrings)) }
