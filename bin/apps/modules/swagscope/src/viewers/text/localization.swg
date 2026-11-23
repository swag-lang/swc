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
    ui_Blanks:       string = "Show Whitespace"        // Option marking each space with a dot and each tabulation with an arrow.
    ui_TabWidth:     string = "Tab Width"              // Option placing a tab stop every 2, 4 or 8 spaces.
    ui_Encoding:     string = "Character Encoding"     // Option choosing how the bytes are read as text.
    ui_ZoomMenu:     string = "Zoom…"                  // Tooltip of the zoom value menu.
    ui_Back:         string = "Back in Text"            // Lens command returning to the previous text destination.
    ui_Forward:      string = "Forward in Text"         // Lens command advancing to the next text destination.
    ui_BookmarkCurrentLine: string = "Bookmark Current Line" // Lens command naming the exact current line.
    ui_BookmarkNameHint: string = "Choose a unique name for this line." // Prompt for a bookmark name.
    ui_BookmarkDefaultName: string = "Line %"            // Suggested name for a bookmarked line.
    ui_BookmarkAdd: string = "Bookmark"                  // Confirmation action when adding a bookmark.
    ui_PreviousBookmark: string = "Previous Bookmark"    // Lens command navigating to the previous named line.
    ui_NextBookmark: string = "Next Bookmark"            // Lens command navigating to the next named line.
    ui_ClearBookmarks: string = "Clear Bookmarks"        // Lens command that opens a clear confirmation.
    ui_ClearBookmarksMessage: string = "Clear all bookmarks in this text file?" // Clear confirmation prompt.
    ui_RenameBookmark: string = "Rename Bookmark %"      // Lens action renaming a named line.
    ui_Rename: string = "Rename"                         // Confirmation action when renaming a bookmark.
    ui_BookmarkLine: string = "Line %"                   // Line detail shown for a bookmark.
    ui_BookmarkStale: string = "File changed"            // Detail shown when bookmarks belong to an older file.
    ui_BookmarkNameInvalid: string = "Bookmark names must be unique, nonempty, and no longer than 128 characters." // Validation error for bookmark names.
    ui_NotText:      string = "This file does not contain readable text. Select Hexadecimal to inspect its bytes."     // No encoding reads the file as text.
    ui_CurrentLine:  string = "line %"                 // Line under the cursor, counted in the whole file.
    ui_CurrentColumn: string = "column %"              // Unicode character column under the cursor.
    ui_CurrentByte:   string = "byte 0x%"              // Absolute file byte offset under the cursor.
    ui_Estimated:     string = "estimated"             // Marks a lens destination inferred from sampled line lengths.
    ui_EstimatedLine: string = "about line %"           // Estimated whole-file line near the cursor.
    ui_EstimatedOffset: string = "near byte 0x%"        // Estimated line destination byte offset.
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
