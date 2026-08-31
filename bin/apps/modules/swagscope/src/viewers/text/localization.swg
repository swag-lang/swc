#global internal

using Core, Gui

// Visible strings of the text viewer.
//
// An encoding is named by its standard spelling, so those names live in the viewer itself rather
// than in this table.
struct TextStrings
{
    ui_Name:     string = "Basic text"                                                                             // Name of this viewer in the viewer selector.
    ui_WrapOn:   string = "Line wrapping on (Ctrl+W)"                                                              // Tooltip while long lines are folded.
    ui_WrapOff:  string = "Line wrapping off (Ctrl+W)"                                                             // Tooltip while long lines run off the edge.
    ui_Encoding: string = "Character encoding"                                                                     // Tooltip of the encoding selector.
    ui_ZoomMenu: string = "Text zoom options"                                                                      // Tooltip of the zoom value menu.
    ui_NotText:  string = "This file does not contain readable text. Select Hexadecimal to inspect its bytes."     // No encoding reads the file as text.
    ui_Details:  string = "%"                                                                                      // Encoding shown beside the file size.
}

private const FrenchStringsName = "lang/fr/scope.text.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.text.tweak")

private var g_TextStrings: TextStrings

// Returns the visible strings of the text viewer in the active language.
func textStrings()->const *TextStrings => &g_TextStrings

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerTextStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'TextStrings(&g_TextStrings, "scope.text")
}

#run
{
    expect Gui.validateStrings'TextStrings(cast(string) FrenchStrings)
}
