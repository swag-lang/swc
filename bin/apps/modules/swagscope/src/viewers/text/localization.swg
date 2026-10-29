#global internal
#global namespace Viewers.PlainText

using Core, Gui

// Visible strings of the text viewer.
//
// An encoding is named by its standard spelling, so those names live in the viewer itself rather
// than in this table.
struct Texts
{
    ui_Name:         string = "Basic Text"             // Name of this viewer in the viewer selector.
    ui_Wrap:         string = "Wrap Long Lines"        // Option folding long lines into the view; Ctrl+W also switches it.
    ui_Numbers:      string = "Line Numbers"           // Option numbering the lines in a gutter.
    ui_Encoding:     string = "Character Encoding"     // Option choosing how the bytes are read as text.
    ui_ZoomMenu:     string = "Text Zoom Options"      // Tooltip of the zoom value menu.
    ui_NotText:      string = "This file does not contain readable text. Select Hexadecimal to inspect its bytes."     // No encoding reads the file as text.
    ui_Details:      string = "% · %"                  // Encoding and the current cursor line.
    ui_DetailsStats: string = "% · % · % · % · %"      // Encoding, current cursor line, and line, word, and Unicode character counts.
    ui_CurrentLine:  string = "line %"                 // Current logical line under the cursor.
    ui_OneLine:      string = "1 line"                 // Singular line count.
    ui_Lines:        string = "% lines"                // Plural line count.
    ui_OneWord:      string = "1 word"                 // Singular word count.
    ui_Words:        string = "% words"                // Plural word count.
    ui_OneCharacter: string = "1 character"            // Singular Unicode character count.
    ui_Characters:   string = "% characters"           // Plural Unicode character count.
}

private const FrenchStringsName = "lang/fr/scope.text.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.text.tweak")

private var g_Texts: Texts

// Returns the visible strings of the text viewer in the active language.
func texts()->const *Texts => &g_Texts

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.text")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
