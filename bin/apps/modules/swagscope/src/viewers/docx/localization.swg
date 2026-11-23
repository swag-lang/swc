#global internal
#global namespace Viewers.Docx

using Core, Gui

// Visible strings of the Word document reader.
struct Texts
{
    ui_Name:                    string = "Word document"
    ui_Preparing:               string = "Preparing document…"
    ui_Details:                 string = "Word document · % paragraphs"
    ui_OneParagraph:            string = "Word document · 1 paragraph"
    ui_OneTable:                string = " · 1 table"
    ui_Tables:                  string = " · % tables"
    ui_OneImageOmitted:         string = " · 1 image not shown"
    ui_ImagesOmitted:           string = " · % images not shown"
    ui_StylesSimplified:        string = " · some styles simplified"
    ui_PageElementsSimplified:  string = " · headers and footers simplified"
    ui_SectionLayoutSimplified: string = " · some section layouts simplified"
    ui_FootnotesTitle:          string = "Footnotes"
    ui_FootnoteOmitted:         string = "[Footnote not shown]"
    ui_FootnotesSimplified:     string = " · some footnotes simplified"
    ui_LinksSimplified:         string = " · some links simplified"
    ui_ImageOmitted:            string = "[Image not shown]"
    err_Invalid:                string = "This Word document has a damaged structure."
    err_TooLarge:               string = "This Word document is too large to open safely."
}

private const FrenchStringsName = "lang/fr/scope.docx.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.docx.tweak")

private var g_Texts: Texts

func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.docx")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
