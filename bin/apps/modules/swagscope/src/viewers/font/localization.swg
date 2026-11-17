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
    ui_CharacterMap:      string = "Character Map"
    ui_NoCharacters:      string = "No mapped characters"
    ui_NotCovered:        string = "None"     // Reading of a Unicode block the face maps no character of.
    ui_ShowCharacter:     string = "Show % in the Character Map"     // Lens row going to the cell of the character typed, or of its U+ code point.
    ui_NotInFont:         string = "Not in this font"     // Faint reading of a typed character the face does not map.
    ui_Regular:           string = "Regular"

    // Weight classes of the OS/2 table, by hundreds from 100; 400 is `ui_Regular`.
    ui_WeightThin:       string = "Thin"
    ui_WeightExtraLight: string = "Extra Light"
    ui_WeightLight:      string = "Light"
    ui_WeightMedium:     string = "Medium"
    ui_WeightSemiBold:   string = "Semibold"
    ui_WeightBold:       string = "Bold"
    ui_WeightExtraBold:  string = "Extra Bold"
    ui_WeightBlack:      string = "Black"

    // Embedding permissions the OS/2 `fsType` declares, named as the OpenType specification
    // names them; the face states them, the viewer draws no conclusion from them.
    ui_EmbedInstallable:  string = "installable"
    ui_EmbedRestricted:   string = "restricted license"
    ui_EmbedPreview:      string = "preview and print"
    ui_EmbedEditable:     string = "editable"
    ui_EmbedNoSubset:     string = "no subsetting"
    ui_EmbedBitmap:       string = "bitmaps only"
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
