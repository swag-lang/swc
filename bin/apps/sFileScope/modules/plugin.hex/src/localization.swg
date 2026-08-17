#global public

using Core, Gui

// Visible strings of the hexadecimal viewer.
//
// The names of the readings a scalar is spelled in — `Hex`, `8-bit`, `Little endian` — are the
// vocabulary of the format itself rather than sentences about it, so a language that writes them
// the same way simply omits them and keeps the reference wording.
struct HexStrings
{
    ui_TipWidth:     string = "Value width"                                          // Tooltip of the scalar width selector.
    ui_Width8:       string = "8-bit"                                                // One byte at a time.
    ui_Width16:      string = "16-bit"                                               // Two bytes at a time.
    ui_Width32:      string = "32-bit"                                               // Four bytes at a time.
    ui_Width64:      string = "64-bit"                                               // Eight bytes at a time.
    ui_TipFormat:    string = "Value representation"                                 // Tooltip of the reading selector.
    ui_FormatHex:    string = "Hex"                                                  // Hexadecimal reading of a scalar.
    ui_FormatUns:    string = "Unsigned"                                             // Unsigned decimal reading of a scalar.
    ui_FormatSigned: string = "Signed"                                               // Signed decimal reading of a scalar.
    ui_FormatFloat:  string = "Float"                                                // Floating-point reading of a 32- or 64-bit scalar.
    ui_Endian:       string = "Little endian"                                        // Label of the byte-order switch.
    ui_TipEndian:    string = "Read multi-byte values in little-endian order"        // Tooltip of the byte-order switch.
    ui_Details:      string = "hex and text · streamed"                              // Summary the host shows beside the file size.
    ui_GoTo:         string = "Go to offset"                                         // Dialog title and menu entry of the jump command.
    ui_GoToMessage:  string = "Hexadecimal offset, or a signed offset from the caret."     // Question of the jump dialog.
    ui_SelectAll:    string = "Select all"                                           // Menu entry selecting the whole file.
    ui_RowWidth:     string = "Bytes per row"                                        // Menu grouping the row-width choices.
    ui_RowAuto:      string = "Fit the window"                                       // Row width following the window width.

    ui_CopyBytes:    string = "Copy bytes"           // Copy the selection as hexadecimal byte pairs.
    ui_CopyText:     string = "Copy text"            // Copy the selection as printable text.
    ui_CopyDump:     string = "Copy dump"            // Copy the selection as an offset/hex/text dump.

    // Copy entries when the selection is larger than what a clipboard should carry. The bound is
    // named on the command itself, because a clipboard that came back short explains nothing.
    ui_CopyBytesMax: string = "Copy the first % as bytes"
    ui_CopyTextMax:  string = "Copy the first % as text"
    ui_CopyDumpMax:  string = "Copy the first % as a dump"
}

private const FrenchStringsName = "lang/fr/filescope.hex.tweak"
private const FrenchStrings = #include("../datas/lang/fr/filescope.hex.tweak")

private var g_HexStrings: HexStrings

// Returns the visible strings of the hexadecimal viewer in the active language.
func hexStrings()->const *HexStrings => &g_HexStrings

// Registers this plugin's string table with the host that loaded it.
//
// A plugin enters the process long after the host chose a language, so its translations are
// published into the host's bundle before the table is registered: [[Gui.registerStrings]] then
// finds them and the viewer opens in the language of the window around it. Calling this again
// is a no-op, so the first view of this format pays for it and no other does.
func registerHexStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'HexStrings(&g_HexStrings, "filescope.hex")
}

#run
{
    expect Gui.validateStrings'HexStrings(cast(string) FrenchStrings)
}
