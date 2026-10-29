#global internal
#global namespace Viewers.Typeface

using Core, Gui

// Visible strings of the font viewer.
struct Texts
{
    ui_DefaultSample:     string = "Sphinx of black quartz"
    ui_SamplePlaceholder: string = "Type sample text"
    ui_EditSample:        string = "Edit Sample Text"
    ui_PreviousPage:      string = "Previous Character Page"
    ui_NextPage:          string = "Next Character Page"
    ui_CharacterRange:    string = "Character Range"
    ui_BasicLatin:        string = "Basic Latin"
    ui_Latin1:            string = "Latin-1 Supplement"
    ui_Greek:             string = "Greek and Coptic"
    ui_Cyrillic:          string = "Cyrillic"
    ui_Symbols:           string = "General Punctuation and Symbols"
    ui_Specimen:          string = "SPECIMEN"
    ui_Glyphs:            string = "Glyphs"
    ui_CharacterMap:      string = "CHARACTER MAP"
    ui_NoCharacters:      string = "No mapped characters"
    ui_Regular:           string = "Regular"
    ui_Metrics:           string = "% · % glyphs · % UPM"
    ui_DetailsSingle:     string = "% · % · % glyphs · % UPM"
    ui_DetailsCollection: string = "% · % · % glyphs · % UPM · % faces"
}

private const FrenchStringsName = "lang/fr/scope.font.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.font.tweak")

private var g_Texts: Texts

// Returns the visible strings of the font viewer in the active language.
func texts()->const *Texts => &g_Texts

// Registers this viewer's string table with the application.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.font")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
