#global public

using Core, Gui

// Visible strings of sFileScope.
//
// The name of the application is a proper name and the name of an encoding is its standard
// spelling, so neither is translated wherever it appears inside one of these sentences.
struct AppStrings
{
    ui_WindowTitle:                    string = "sFileScope — Universal viewer"                                                          // Title of the application window.
    ui_Open:                           string = "Open"                                                                                   // Tooltip of the open-file button.
    ui_OpenDefault:                    string = "Open with default application"                                                          // Tooltip of the system-default application button.
    ui_Viewer:                         string = "Viewer"                                                                                 // Tooltip of the viewer selector.
    ui_BasicText:                      string = "Basic text"                                                                             // Name of the host's own text viewer in that selector.
    ui_WrapOn:                         string = "Line wrapping on (Ctrl+W)"                                                              // Tooltip while long lines are folded.
    ui_WrapOff:                        string = "Line wrapping off (Ctrl+W)"                                                             // Tooltip while long lines run off the edge.
    ui_Encoding:                       string = "Character encoding"                                                                     // Tooltip of the encoding selector.
    ui_Files:                          string = "Files beside this one"                                                                  // Tooltip of the file-panel button.
    ui_FullScreen:                     string = "Full screen (F11)"                                                                      // Tooltip of the enter-full-screen button.
    ui_ExitFullScreen:                 string = "Exit full screen (F11)"                                                                 // Tooltip of the leave-full-screen button.
    ui_SameKind:                       string = "Only files of the same kind"                                                            // Tooltip of the folder-navigation filter toggle.
    ui_Recent:                         string = "Recent"                                                                                 // Panel section listing what was read before.
    ui_ClearHistory:                   string = "Clear history"                                                                          // Tooltip of the clear-history button.
    ui_ConfirmClearHistory:            string = "The whole file history will be cleared."                                                // Consequence stated before confirming that the recent list is emptied.
    ui_Folder:                         string = "Folder"                                                                                 // Panel section listing the current folder, before one is open.
    ui_FolderHistory:                  string = "Recent folders"                                                                         // Tooltip of the folder-history menu button.
    ui_NotText:                        string = "This file does not contain readable text. Select Hexadecimal to inspect its bytes."     // No encoding reads it as text.
    ui_MenuLocate:                     string = "Show this file in its folder"                                                           // Panel menu entry selecting the file in the system file explorer.
    ui_MenuOpenDefault:                string = "Open with default application"                                                          // File menu entry launching the registered system handler.
    ui_MenuOpenWith:                   string = "Open with another application…"                                                         // Panel menu entry offering the system application chooser.
    ui_MenuCopyPath:                   string = "Copy full path"                                                                         // Panel menu entry copying the complete file name.
    ui_MenuCopyName:                   string = "Copy file name"                                                                         // Panel menu entry copying the final path component.
    ui_MenuForget:                     string = "Remove this file from the history"                                                      // Panel menu entry dropping one file from the recent list.
    ui_Search:                         string = "Find in document"                                                                       // Placeholder of the search field.
    ui_SearchPrevious:                 string = "Previous match (Shift+F3)"                                                              // Tooltip of the previous-match button.
    ui_SearchNext:                     string = "Next match (F3)"                                                                        // Tooltip of the next-match button.
    ui_SearchOptions:                  string = "Search options"                                                                         // Tooltip of the search-options menu button.
    ui_SearchMatchCase:                string = "Match case"                                                                             // Search-options menu entry for case-sensitive matching.
    ui_SearchWholeWord:                string = "Match whole words"                                                                      // Search-options menu entry for complete-word matching.
    ui_SearchRegularExpression:        string = "Use regular expression"                                                                 // Search-options menu entry enabling regexp syntax.
    ui_SearchInvalidRegularExpression: string = "Invalid regular expression"                                                             // Status tooltip for regexp syntax that cannot be compiled.
    ui_NoMatch:                        string = "No match"                                                                               // Status line when a search reached the end with nothing.
    ui_Searching:                      string = "Searching…"                                                                             // Status line while a search scans the file.
    ui_DropTitle:                      string = "Drop a file to view it"                                                                 // Invitation shown while no file is open.
    ui_DropHint:                       string = "or open one with Ctrl+O"                                                                // Secondary invitation shown while no file is open.
    ui_TextDetails:                    string = "% · streamed"                                                                           // Summary of the basic text viewer, starting with its encoding.
    ui_Unsupported:                    string = "No viewer can show this file."                                                          // No viewer claimed the file.
    ui_OpenStopped:                    string = "The file could not be shown."                                                           // A viewer refused the file it claimed.
    ui_ViewerError:                    string = "This viewer could not decode the file."                                                 // Heading above a viewer's exact decoder error.
    dlg_TitleOpen:                     string = "Open a file"                                                                            // Title of the open dialog.
    dlg_ButtonOpen:                    string = "Open"                                                                                   // Confirmation button of the open dialog.
    dlg_AllFiles:                      string = "All files"                                                                              // Filter matching every extension.
}

private const FrenchStringsName = "lang/fr/filescope.tweak"
private const FrenchStrings     = #include("../datas/lang/fr/filescope.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of sFileScope in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Registers the sFileScope string table and its embedded translations.
//
// The resource is published before the table is registered: [[Gui.registerStrings]] translates a
// table only after it can find that table's translation file.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)

    // The file name here becomes `lang/<tag>/filescope.tweak`, which must be the exact resource
    // name published above: a mismatch does not fail, it silently shows English.
    Gui.registerStrings'AppStrings(&g_AppStrings, "filescope")
}

#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
