#global internal
#global namespace Viewers.Pptx

using Core, Gui

struct Texts
{
    ui_ReadNotes:    string = "Read Speaker Notes"
    ui_NotesMode:    string = "speaker notes"
    ui_NoNotes:      string = "This slide has no speaker notes."
    ui_Previous:     string = "Previous Slide"
    ui_Next:         string = "Next Slide"
    ui_ShowSlides:   string = "Show Slides"
    ui_ReadText:     string = "Read Slide Text"
    ui_TextMode:     string = "text view"
    ui_Simplified:   string = "simplified layout"
    ui_CurrentSlide: string = "Presentation · slide % of %"
    ui_Name:         string = "Presentation"
    ui_Preparing:    string = "Preparing presentation…"
    ui_Details:      string = "Presentation · % slides · % images not shown"
    ui_Slide:        string = "Slide %"
    ui_Thumbnails:   string = "Slides"
    ui_ImageOmitted: string = "[Image not shown]"
    err_Invalid:     string = "This presentation has a damaged structure."
    err_TooLarge:    string = "This presentation is too large to open safely."
    err_LegacyFormat: string = "Legacy PowerPoint .ppt and .pps files are not supported; open a .pptx, .ppsx, or .pptm file."
    err_TemplateFormat: string = "PowerPoint template files are not supported."
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
