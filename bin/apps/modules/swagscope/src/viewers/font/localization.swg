#global internal

using Core, Gui

// Visible strings of the font viewer.
struct FontStrings
{
    ui_DefaultSample:     string = "Sphinx of black quartz"
    ui_SamplePlaceholder: string = "Type sample text"
    ui_PreviousPage:      string = "Previous character page"
    ui_NextPage:          string = "Next character page"
    ui_CharacterRange:    string = "Character range"
    ui_BasicLatin:        string = "Basic Latin"
    ui_Latin1:            string = "Latin-1 supplement"
    ui_Greek:             string = "Greek and Coptic"
    ui_Cyrillic:          string = "Cyrillic"
    ui_Symbols:           string = "General punctuation and symbols"
    ui_Specimen:          string = "SPECIMEN"
    ui_CharacterMap:      string = "CHARACTER MAP"
    ui_NoCharacters:      string = "No mapped characters"
    ui_Regular:           string = "Regular"
    ui_Metrics:           string = "% · % glyphs · % UPM"
    ui_DetailsSingle:     string = "% · % · % glyphs · % UPM"
    ui_DetailsCollection: string = "% · % · % glyphs · % UPM · % faces"
}

private const FrenchStringsName = "lang/fr/scope.font.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.font.tweak")

private var g_FontStrings: FontStrings

// Returns the visible strings of the font viewer in the active language.
func fontStrings()->const *FontStrings => &g_FontStrings

// Registers this viewer's string table with the application.
func registerFontStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'FontStrings(&g_FontStrings, "scope.font")
}

#run
{
    expect Gui.validateStrings'FontStrings(cast(string) FrenchStrings)
}
