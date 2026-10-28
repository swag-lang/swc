#global internal
#global namespace Viewers.Hex

using Core, Gui

// Visible strings of the hexadecimal viewer.
//
// The names of the readings a scalar is spelled in — `Hex`, `8-bit`, `Little endian` — are the
// vocabulary of the format itself rather than sentences about it, so a language that writes them
// the same way simply omits them and keeps the reference wording.
struct Texts
{
    ui_ValueWidth:             string = "Value width"                                                                                         // Option choosing how many bytes make one value.
    ui_Width8:                 string = "8-bit"                                                                                               // One byte at a time.
    ui_Width16:                string = "16-bit"                                                                                              // Two bytes at a time.
    ui_Width32:                string = "32-bit"                                                                                              // Four bytes at a time.
    ui_Width64:                string = "64-bit"                                                                                              // Eight bytes at a time.
    ui_Representation:         string = "Value representation"                                                                                // Option choosing how a value is spelled.
    ui_FormatHex:              string = "Hex"                                                                                                 // Hexadecimal reading of a scalar.
    ui_FormatUns:              string = "Unsigned"                                                                                            // Unsigned decimal reading of a scalar.
    ui_FormatSigned:           string = "Signed"                                                                                              // Signed decimal reading of a scalar.
    ui_FormatFloat:            string = "Float"                                                                                               // Floating-point reading of a 32- or 64-bit scalar.
    ui_EndianLittle:           string = "Little endian"                                                                                       // Little-endian byte-order choice.
    ui_EndianBig:              string = "Big endian"                                                                                          // Big-endian byte-order choice.
    ui_ByteOrder:              string = "Byte order"                                                                                          // Option choosing the byte order of multi-byte values.
    ui_ZoomMenu:               string = "Byte View Zoom Options"                                                                              // Tooltip of the zoom value menu.
    ui_TextColumn:             string = "text"                                                                                                // Header of the decoded-text column.
    ui_Empty:                  string = "This file is empty."                                                                                 // Message painted when the file has no bytes.
    ui_GoTo:                   string = "Go to Offset"                                                                                        // Dialog title and menu entry of the jump command.
    ui_GoToMessage:            string = "Hexadecimal or 0d decimal offset, percentage, caret, filesize, or signed caret-relative offset."     // Question of the jump dialog.
    ui_SelectAll:              string = "Select All"                                                                                          // Menu entry selecting the whole file.
    ui_RowWidth:               string = "Bytes per row"                                                                                       // Option choosing how many bytes one row shows.
    ui_RowAuto:                string = "Fit the window"                                                                                      // Row width following the window width.
    ui_SearchPlaceholder:      string = "Hex, text:, or value:"                                                                               // Placeholder naming the three binary query forms.
    ui_SearchHelp:             string = "Use hex bytes and ? wildcards; prefix exact UTF-8 with text: or the active scalar with value:."      // Tooltip explaining binary query syntax.
    ui_SearchPatternError:     string = "Use hexadecimal byte pairs with ??, ?A, or A? wildcards."                                            // Invalid hexadecimal pattern.
    ui_SearchValueError:       string = "Enter a value that fits the active width and representation."                                        // Invalid active scalar.
    ui_InspectorEmpty:         string = "No bytes at the caret"                                                                               // Inline inspector before a byte is available.
    ui_Analysis:               string = "Analysis"                                                                                            // Heading of the byte-analysis panel.
    ui_AnalysisTip:            string = "Analyze the selection, or the whole file when one byte is selected"                                  // Tooltip of the visible analysis action.
    ui_AnalysisRun:            string = "Analyze the current selection, or the whole file when one byte is selected"                          // Tooltip of the repeated analysis action.
    ui_AnalysisCancel:         string = "Stop Analysis"                                                                                       // Tooltip of the cancellation action.
    ui_AnalysisClose:          string = "Close Analysis"                                                                                      // Tooltip of the panel close action.
    ui_AnalysisFile:           string = "Whole file · %"                                                                                      // Scope of a whole-file analysis.
    ui_AnalysisSelection:      string = "Selection @% · %"                                                                                    // Scope of a selected-range analysis.
    ui_AnalysisProgress:       string = "Analyzing · %{f1}%%"                                                                                 // Progress through the selected range.
    ui_AnalysisCancelled:      string = "Stopped after %"                                                                                     // Cancelled partial analysis.
    ui_AnalysisMetrics:        string = "Entropy %{f2}/8 · zero %{f1}%% · printable %{f1}%%"                                                  // Compact byte-distribution metrics.
    ui_AnalysisNoBytes:        string = "No bytes were analyzed"                                                                              // Empty analysis result.
    ui_AnalysisByteHint:       string = "Point at the byte map to inspect an exact count"                                                     // Histogram interaction hint.
    ui_AnalysisByte:           string = "Byte %{X02} · % occurrences · %{f2}%%"                                                               // Exact count under the histogram pointer.
    ui_AnalysisByteOnce:       string = "Byte %{X02} · 1 occurrence · %{f2}%%"                                                                // The same, for a byte seen once.
    ui_AnalysisStrings:        string = "Inferred strings"                                                                                    // Heading before string extraction completes.
    ui_AnalysisStringsCount:   string = "% inferred strings"                                                                                  // Complete inferred-string count.
    ui_AnalysisOneString:      string = "1 inferred string"                                                                                   // The same, for a single string.
    ui_AnalysisStringsLimited: string = "First % inferred strings · result limit reached"                                                     // Bounded inferred-string count.
    ui_AnalysisAscii:          string = "ASCII"                                                                                               // Inferred single-byte text.
    ui_AnalysisUtf16Little:    string = "UTF-16 LE"                                                                                           // Inferred little-endian wide text.
    ui_AnalysisUtf16Big:       string = "UTF-16 BE"                                                                                           // Inferred big-endian wide text.
    ui_AnalysisOffset:         string = "Offset"                                                                                              // String-table source offset column.
    ui_AnalysisEncoding:       string = "Encoding"                                                                                            // String-table inference column.
    ui_AnalysisText:           string = "Text"                                                                                                // String-table preview column.
    err_AnalysisShortRead:     string = "The file ends before the analysis range"                                                             // Failure when a file changes while it is being analyzed.

    ui_CopyBytes: string = "Copy Bytes"     // Menu entry copying the selection as hexadecimal byte pairs.
    ui_CopyText:  string = "Copy Text"      // Menu entry copying the selection as printable text.
    ui_CopyDump:  string = "Copy Dump"      // Menu entry copying the selection as an offset/hex/text dump.

    // Copy entries when the selection is larger than what a clipboard should carry. The bound is
    // named on the command itself, because a clipboard that came back short explains nothing.
    ui_CopyBytesMax: string = "Copy the First % as Bytes"
    ui_CopyTextMax:  string = "Copy the First % as Text"
    ui_CopyDumpMax:  string = "Copy the First % as a Dump"
    err_Read:        string = "file stream could not be read"     // Diagnostics of a file the viewer cannot read.
    err_Truncated:   string = "file ends before its reported size"
}

private const FrenchStringsName = "lang/fr/scope.hex.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.hex.tweak")

private var g_Texts: Texts

// Returns the visible strings of the hexadecimal viewer in the active language.
func texts()->const *Texts => &g_Texts

// Names a row width the options offer: the window's own, or a count of bytes.
func rowWidthName(index: u32)->string
{
    switch index
    {
    case 0:  return texts().ui_RowAuto
    case 1:  return "8"
    case 2:  return "16"
    case 3:  return "32"
    default: return "64"
    }
}

// Names a value width the options offer.
func valueWidthName(index: u32)->string
{
    switch index
    {
    case 0:  return texts().ui_Width8
    case 1:  return texts().ui_Width16
    case 2:  return texts().ui_Width32
    default: return texts().ui_Width64
    }
}

// Names a representation the options offer.
func formatName(index: u32)->string
{
    switch index
    {
    case 0:  return texts().ui_FormatHex
    case 1:  return texts().ui_FormatUns
    case 2:  return texts().ui_FormatSigned
    default: return texts().ui_FormatFloat
    }
}

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.hex")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
