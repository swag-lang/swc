#global public

using Core, Gui

// Visible strings of sFileScope.
//
// The name of the application is a proper name and the name of an encoding is its standard
// spelling, so neither is translated wherever it appears inside one of these sentences.
struct AppStrings
{
    ui_WindowTitle: string = "sFileScope — Universal viewer"               // Title of the application window.
    ui_Open:        string = "Open"                                        // Tooltip of the open-file button.
    ui_Previous:    string = "Previous file"                               // Tooltip of the previous-file button.
    ui_Next:        string = "Next file"                                   // Tooltip of the next-file button.
    ui_Viewer:      string = "Viewer"                                      // Tooltip of the viewer selector.
    ui_BasicText:   string = "Basic text"                                  // Name of the host's own text viewer in that selector.
    ui_WrapOn:      string = "Wrap on"                                     // Wrapping button while long lines are folded.
    ui_WrapOff:     string = "Wrap off"                                    // Wrapping button while long lines run off the edge.
    ui_Encoding:    string = "Character encoding"                          // Tooltip of the encoding selector.
    ui_Files:       string = "Files beside this one"                       // Tooltip of the file-panel button.
    ui_Recent:      string = "Recent"                                      // Panel section listing what was read before.
    ui_Folder:      string = "Folder"                                      // Panel section listing the current folder, before one is open.
    ui_NotText:     string = "This file does not contain readable text. Select Hexadecimal to inspect its bytes."     // No encoding reads it as text.
    ui_Search:      string = "Find in document"                            // Placeholder of the search field.
    ui_NoMatch:     string = "No match"                                    // Status line when a search reached the end with nothing.
    ui_Searching:   string = "Searching…"                                  // Status line while a search scans the file.
    ui_DropTitle:   string = "Drop a file to view it"                      // Invitation shown while no file is open.
    ui_Ready:       string = "Ready"                                       // Neutral status line.
    ui_Unsupported: string = "No installed plugin can show this file."     // No viewer claimed the file.
    ui_OpenStopped: string = "The file could not be shown."                // A viewer refused the file it claimed.
    dlg_TitleOpen:  string = "Open a file"                                 // Title of the open dialog.
    dlg_ButtonOpen: string = "Open"                                        // Confirmation button of the open dialog.
    dlg_AllFiles:   string = "All files"                                   // Filter matching every extension.
}

private const FrenchStringsName = "lang/fr/filescope.tweak"
private const FrenchStrings = #include("../datas/lang/fr/filescope.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of sFileScope in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Registers the sFileScope string table and its embedded translations.
//
// The resource is published before the table is registered, which is the order every plugin
// follows too: [[Gui.registerStrings]] translates a table it can already find a file for.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'AppStrings(&g_AppStrings, "sfilescope")
}

#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
