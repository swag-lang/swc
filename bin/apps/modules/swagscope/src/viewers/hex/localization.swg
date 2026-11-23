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
    ui_ValueWidth:             string = "Value Width"                                                                                         // Option choosing how many bytes make one value.
    ui_Width8:                 string = "8-bit"                                                                                               // One byte at a time.
    ui_Width16:                string = "16-bit"                                                                                              // Two bytes at a time.
    ui_Width32:                string = "32-bit"                                                                                              // Four bytes at a time.
    ui_Width64:                string = "64-bit"                                                                                              // Eight bytes at a time.
    ui_Representation:         string = "Value Representation"                                                                                // Option choosing how a value is spelled.
    ui_FormatHex:              string = "Hex"                                                                                                 // Hexadecimal reading of a scalar.
    ui_FormatUns:              string = "Unsigned"                                                                                            // Unsigned decimal reading of a scalar.
    ui_FormatSigned:           string = "Signed"                                                                                              // Signed decimal reading of a scalar.
    ui_FormatFloat:            string = "Float"                                                                                               // Floating-point reading of a 32- or 64-bit scalar.
    ui_EndianLittle:           string = "Little Endian"                                                                                       // Little-endian byte-order choice.
    ui_EndianBig:              string = "Big Endian"                                                                                          // Big-endian byte-order choice.
    ui_ByteOrder:              string = "Byte Order"                                                                                          // Option choosing the byte order of multi-byte values.
    ui_ZoomMenu:               string = "Zoom…"                                                                                               // Tooltip of the zoom value menu.
    ui_Empty:                  string = "This file is empty."                                                                                 // Message painted when the file has no bytes.
    ui_GoTo:                   string = "Go to Offset"                                                                                        // Dialog title and menu entry of the jump command.
    ui_Back:                   string = "Back"                                                                                                // Lens command returning to the previous explicit offset.
    ui_Forward:                string = "Forward"                                                                                             // Lens command advancing to the next explicit offset.
    ui_SetBookmark:            string = "Bookmark Current Offset"                                                                             // Lens action storing this document session's current byte position.
    ui_GoToBookmark:           string = "Go to Bookmarked Offset (%)"                                                                         // Lens action returning to the stored byte position.
    ui_GoToMessage:            string = "Hex, 0d decimal, percentage, caret, filesize, bookmark or base; use +, -, *, /, parentheses or align(value, boundary). A leading sign is relative to the caret." // Expression forms accepted by Go To.
    ui_SetBaseAddress:        string = "Set Base Address"                                                                                   // Lens action choosing the virtual address mapped to offset zero.
    ui_BaseAddressMessage:    string = "Hexadecimal or 0d decimal virtual address; enter zero to clear it."                                  // Question of the base-address dialog.
    ui_SelectAll:              string = "Select All"                                                                                          // Menu entry selecting the whole file.
    ui_RowWidth:               string = "Bytes per Row"                                                                                       // Option choosing how many bytes one row shows.
    ui_RowAuto:                string = "Fit the Window"                                                                                      // Row width following the window width.
    ui_SearchPlaceholder:      string = "Hex, text:, value:, selection:, or range:"                                                          // Placeholder naming the binary query forms and byte scopes.
    ui_SearchHelp:             string = "Use selection: for selected bytes or range:offset:length:pattern for an explicit range. Bare numbers and 0x are hex; 0d is decimal. Add hex:, text:, or value: for the pattern form. ? matches a nibble." // Tooltip explaining binary query syntax.
    ui_SearchSelectionRequired: string = "Select bytes before using selection:"                                                               // Error when selection scope has no active byte selection.
    ui_SearchRangeInvalid:     string = "Use range:offset:length:pattern with a nonzero range inside the file; bare numbers and 0x are hex, 0d is decimal." // Invalid, empty, or out-of-file explicit byte range.
    ui_SearchPatternError:     string = "Use hexadecimal byte pairs with ??, ?A, or A? wildcards."                                            // Invalid hexadecimal pattern.
    ui_SearchValueError:       string = "Enter a value that fits the active width and representation."                                        // Invalid active scalar.
    ui_InspectorAt:            string = "% at 0x%"                                                                                            // What the inspector read its value as, and where; placeholders: the reading, the offset.
    ui_InspectorFloat16:       string = "f16"                                                                                                // IEEE-754 binary16 reading of the caret bytes.
    ui_InspectorIpv4:          string = "IPv4"                                                                                               // Dotted decimal address from four consecutive caret bytes.
    ui_InspectorIpv6:          string = "IPv6"                                                                                               // Eight network-order groups from sixteen consecutive caret bytes.
    ui_InspectorGuid:          string = "GUID"                                                                                               // Canonical hexadecimal GUID spelling from sixteen consecutive bytes.
    ui_InspectorBcd:           string = "BCD"                                                                                                // Signed packed-decimal reading from the caret.
    ui_InspectorUleb128:       string = "ULEB128"                                                                                            // Unsigned LEB128 reading from the caret.
    ui_InspectorSleb128:       string = "SLEB128"                                                                                            // Signed LEB128 reading from the caret.
    ui_ReadingInvalid:         string = "invalid"                                                                                             // A domain reading whose bytes exceed its encoding rules.
    ui_DetailsCaret:           string = "%{f1}%% · value % · caret %/%"                                                                        // Whole-file percentage, active value, caret in hex and decimal.
    ui_DetailsSelection:       string = "%{f1}%% · value % · sel %–% (%–%) · len %/% · caret %/%"                                               // Percentage, value, selection bounds/length and caret in both radices.
    ui_Analysis:               string = "Analysis"                                                                                            // Heading of the byte-analysis panel.
    ui_AnalysisTip:            string = "Analyze the selection, or the whole file when there is no selection"                               // Tooltip of the visible analysis action.
    ui_AnalysisRun:            string = "Analyze the current selection, or the whole file when there is no selection"                       // Tooltip of the repeated analysis action.
    ui_AnalysisCancel:         string = "Stop Analysis"                                                                                       // Tooltip of the cancellation action.
    ui_AnalysisClose:          string = "Close Analysis"                                                                                      // Tooltip of the panel close action.
    ui_AnalysisAlgorithms:     string = "Checksum Algorithms"                                                                                // Opens the checksum selection for future analyses.
    ui_AnalysisCrc32:          string = "CRC-32"                                                                                             // Selects CRC-32 checksums.
    ui_AnalysisCrc64:          string = "CRC-64/ECMA-182"                                                                                   // Selects CRC-64/ECMA-182 checksums.
    ui_AnalysisMd5:            string = "MD5"                                                                                                // Selects MD5 digests.
    ui_AnalysisSha1:           string = "SHA-1"                                                                                              // Selects SHA-1 digests.
    ui_AnalysisSha256:         string = "SHA-256"                                                                                            // Selects SHA-256 digests.
    ui_AnalysisSha512:         string = "SHA-512"                                                                                            // Selects SHA-512 digests.
    ui_AnalysisBlake2s:        string = "BLAKE2s-256"                                                                                       // Selects 256-bit BLAKE2s digests.
    ui_AnalysisBlake2b:        string = "BLAKE2b-512"                                                                                       // Selects 512-bit BLAKE2b digests.
    ui_AnalysisFile:           string = "Whole file · %"                                                                                      // Scope of a whole-file analysis.
    ui_AnalysisSelection:      string = "Selection @% · %"                                                                                    // Scope of a selected-range analysis.
    ui_AnalysisProgress:       string = "Analyzing · %{f1}%%"                                                                                 // Progress through the selected range.
    ui_AnalysisCancelled:      string = "Stopped after %"                                                                                     // Cancelled partial analysis.
    ui_AnalysisMetrics:        string = "Entropy %{f2}/8 · zero %{f1}%% · printable %{f1}%%"                                                  // Compact byte-distribution metrics.
    ui_AnalysisEntropyBlocks:  string = "Entropy by Block · select a block to inspect its bytes"                                             // Heading for bounded per-range entropy samples.
    ui_AnalysisEntropy:        string = "Bits/byte"                                                                                           // Entropy column header for one block.
    ui_AnalysisFindings:       string = "Strings · 64 KiB Repeats"                                                                            // Heading for the shared navigable findings list.
    ui_AnalysisRepeatedBlockKind: string = "Block"                                                                                            // Type of one repeated-block occurrence.
    ui_AnalysisRepeatDetail:   string = "At %"                                                                                               // Other exact occurrence; every finding is 64 KiB.
    ui_AnalysisRepeatLimited:  string = "Findings · repeat limit reached"                                                                      // Visible status when a repeated-block result cap is hit.
    ui_AnalysisRepeatLimitsTip: string = "At most 256 distinct blocks and 256 repeated pairs are retained."                                  // Tooltip explaining the detector bounds.
    ui_AnalysisNoBytes:        string = "No bytes were analyzed"                                                                              // Empty analysis result.
    ui_AnalysisDigests:        string = "Checksums calculated: %"                                                                            // Number of checksum algorithms used by the completed analysis.
    ui_AnalysisCopyCrc64:      string = "Copy CRC-64 with Its Byte Range"                                                                     // Lens action copying the checksum and source range.
    ui_AnalysisCopyCrc32:      string = "Copy CRC-32 with Its Byte Range"                                                                     // Lens action copying the checksum and source range.
    ui_AnalysisCopySha256:     string = "Copy SHA-256 with Its Byte Range"                                                                  // Lens action copying the digest of the last complete analysis.
    ui_AnalysisCopyMd5:        string = "Copy MD5 with Its Byte Range"                                                                      // Lens action copying the MD5 digest of the last complete analysis.
    ui_AnalysisCopySha1:       string = "Copy SHA-1 with Its Byte Range"                                                                    // Lens action copying the SHA-1 digest of the last complete analysis.
    ui_AnalysisCopySha512:     string = "Copy SHA-512 with Its Byte Range"                                                                    // Lens action copying the digest and source range.
    ui_AnalysisCopyBlake2s:    string = "Copy BLAKE2s-256 with Its Byte Range"                                                               // Lens action copying the digest and source range.
    ui_AnalysisCopyBlake2b:    string = "Copy BLAKE2b-512 with Its Byte Range"                                                               // Lens action copying the digest and source range.
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
    ui_AnalysisType:           string = "Type"                                                                                                // Kind of one navigable finding.
    ui_AnalysisDetails:        string = "Details"                                                                                             // Text or counterpart range for one finding.
    ui_AnalysisEncoding:       string = "Encoding"                                                                                            // String-table inference column.
    ui_AnalysisText:           string = "Text"                                                                                                // String-table preview column.
    err_AnalysisShortRead:     string = "The file ends before the analysis range"                                                             // Failure when a file changes while it is being analyzed.

    ui_CopyBytes:   string = "Copy Bytes"             // Menu entry copying the selection as hexadecimal byte pairs.
    ui_CopyText:    string = "Copy Text"              // Menu entry copying the selection as printable text.
    ui_CopyDump:    string = "Copy Dump"              // Menu entry copying the selection as an offset/hex/text dump.
    ui_CopyFormats: string = "Other Copy Formats"     // Tooltip of the compact menu for alternate selection spellings.
    ui_CopyOffset:  string = "Copy Offset %"          // Lens command copying the offset of the caret in hexadecimal.
    ui_CopyValue:   string = "Copy Inspected Value"   // Lens command copying the value shown in the inspector.
    ui_CopyReading: string = "Copy % Reading"         // Lens command copying one inspector reading.

    // Copy entries when the selection is larger than what a clipboard should carry. The bound is
    // named on the command itself, because a clipboard that came back short explains nothing.
    ui_CopyBytesMax: string = "Copy the First % as Bytes"
    ui_CopyTextMax:  string = "Copy the First % as Text"
    ui_CopyDumpMax:  string = "Copy the First % as a Dump"
    err_Read:        string = "file stream could not be read"     // Diagnostics of a file the viewer cannot read.
    err_Truncated:   string = "file ends before its reported size"
}

private const HexFrenchStringsName = "lang/fr/scope.hex.tweak"
private const HexFrenchStrings     = #include("../../../datas/lang/fr/scope.hex.tweak")

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
    app.resources.addEmbedded(HexFrenchStringsName, HexFrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.hex")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, HexFrenchStrings))
}
