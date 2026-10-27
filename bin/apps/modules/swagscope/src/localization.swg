#global public

using Core, Gui

// Visible strings of Swag Scope.
//
// The name of the application is a proper name and the name of an encoding is its standard
// spelling, so neither is translated wherever it appears inside one of these sentences.
struct AppStrings
{
    explore_Panels:            string = "History and folders"         // Toggles the exploration sidebar.
    explore_Folders:           string = "Subfolders"                  // Sidebar navigation through the current location.
    explore_Open:              string = "Explore folder (Ctrl+E)"     // Exploration control or status.
    explore_Back:              string = "Back"                        // Exploration control or status.
    explore_Forward:           string = "Forward"                     // Exploration control or status.
    explore_Up:                string = "Parent folder"               // Exploration control or status.
    explore_Refresh:           string = "Refresh"                     // Exploration control or status.
    explore_Names:             string = "Names"                       // Exploration control or status.
    explore_Details:           string = "Details"                     // Exploration control or status.
    explore_Small:             string = "Small thumbnails"            // Exploration control or status.
    explore_Medium:            string = "Medium thumbnails"           // Exploration control or status.
    explore_Large:             string = "Large thumbnails"            // Exploration control or status.
    explore_Name:              string = "Name"                        // Exploration control or status.
    explore_Type:              string = "Type"                        // Exploration control or status.
    explore_Size:              string = "Size"                        // Exploration control or status.
    explore_Modified:          string = "Modified"                    // Exploration control or status.
    explore_Loading:           string = "Reading folder…"             // Exploration control or status.
    explore_Empty:             string = "No files to show"            // Exploration control or status.
    explore_OneItem:           string = "1 item"                      // Exploration control or status.
    explore_Count:             string = "% items"                     // Exploration control or status.
    explore_NotFound:          string = "Location not found"          // Exploration control or status.
    explore_MediaOptions:      string = "Online media options"
    explore_OnlineMovies:      string = "Use online movie posters and details"
    explore_ChooseMusic:       string = "Choose MusicBrainz release group ID…"
    explore_ChooseMusicHelp:   string = "Enter the release group ID from MusicBrainz. Leave empty to use automatic matching."
    explore_InvalidMusicId:    string = "Enter a valid MusicBrainz release group ID."
    explore_ChosenMusicFailed: string = "Could not load the chosen release. Check its MusicBrainz ID and your connection."
    explore_MovieDate:         string = "Released: %"
    explore_MovieOverview:     string = "Synopsis: %"
    explore_ImdbRating:        string = "IMDb rating via Wikidata: %"
    explore_MovieDirector:     string = "Director: %"
    explore_MovieCast:         string = "Cast: %"
    explore_OnlineMusic:       string = "Use online music covers and details"
    explore_MusicArtist:       string = "Artist: %"
    explore_MusicDate:         string = "First release: %"
    ui_AboutWikiNotice:        string = "Film information and summaries come from Wikipedia and Wikidata. Wikipedia text is available under CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/. Each film links to its source article."

    ui_WindowTitle:                    string = "Swag Scope — Universal viewer"               // Title of the application window.
    ui_Open:                           string = "Open (Ctrl+O)"                               // Tooltip of the open-file button.
    ui_OpenDefault:                    string = "Open with default application"               // Tooltip of the system-default application button.
    ui_CloseFile:                      string = "Close file"                                  // Tooltip of the close-file button.
    ui_Viewer:                         string = "Viewer"                                      // Tooltip of the viewer selector.
    ui_Files:                          string = "Files beside this one"                       // Tooltip of the file-panel button.
    ui_FullScreen:                     string = "Full screen (F11)"                           // Tooltip of the enter-full-screen button.
    ui_ExitFullScreen:                 string = "Exit full screen (F11)"                      // Tooltip of the leave-full-screen button.
    ui_SameKind:                       string = "Only files of the same kind"                 // Tooltip of the folder-navigation filter toggle.
    ui_Options:                        string = "Options"                                     // Tooltip of the button opening the options of a viewer.
    ui_PlayMode:                       string = "Play mode"                                   // Tooltip of the play-mode button, and its row among the options.
    ui_PlayOnce:                       string = "Stop at the end"                             // Play-mode entry leaving a played file where it ended.
    ui_PlayRepeat:                     string = "Repeat the file"                             // Play-mode entry replaying the same file.
    ui_PlayFolder:                     string = "Play the folder in order"                    // Play-mode entry continuing with the next file of the same kind.
    ui_PlayShuffle:                    string = "Play the folder shuffled"                    // Play-mode entry continuing with a random file of the same kind.
    ui_PlaySlide:                      string = "Time per picture"                            // Option choosing how long a still picture stays.
    ui_Recent:                         string = "Recent"                                      // Panel section listing what was read before.
    ui_ClearHistory:                   string = "Clear history"                               // Tooltip of the clear-history button.
    ui_ConfirmClearHistory:            string = "The whole file history will be cleared."     // Consequence stated before confirming that the recent list is emptied.
    ui_Folder:                         string = "Folder"                                      // Panel section listing the current folder, before one is open.
    ui_FilterFiles:                    string = "Filter files by name"                        // Placeholder of the current-folder file filter.
    ui_FolderHistory:                  string = "Recent folders"                              // Tooltip of the folder-history menu button.
    ui_MenuLocate:                     string = "Show this file in its folder"                // Panel menu entry selecting the file in the system file explorer.
    ui_MenuOpenDefault:                string = "Open with default application"               // File menu entry launching the registered system handler.
    ui_MenuOpenWith:                   string = "Open with another application…"              // Panel menu entry offering the system application chooser.
    ui_MenuCopyPath:                   string = "Copy full path"                              // Panel menu entry copying the complete file name.
    ui_MenuCopyName:                   string = "Copy file name"                              // Panel menu entry copying the final path component.
    ui_MenuForget:                     string = "Remove this file from the history"           // Panel menu entry dropping one file from the recent list.
    ui_Search:                         string = "Find in document"                            // Placeholder of the search field.
    ui_SearchPrevious:                 string = "Previous match (Shift+F3)"                   // Tooltip of the previous-match button.
    ui_SearchNext:                     string = "Next match (F3)"                             // Tooltip of the next-match button.
    ui_SearchOptions:                  string = "Search options"                              // Tooltip of the search-options menu button.
    ui_SearchMode:                     string = "Search"                                      // Shared query mode that finds occurrences.
    ui_FilterMode:                     string = "Filter"                                      // Shared query mode that limits visible viewer rows.
    ui_SearchMatchCase:                string = "Match case"                                  // Search-options menu entry for case-sensitive matching.
    ui_SearchWholeWord:                string = "Match whole words"                           // Search-options menu entry for complete-word matching.
    ui_SearchRegularExpression:        string = "Use regular expression"                      // Search-options menu entry enabling regexp syntax.
    ui_SearchInvalidRegularExpression: string = "Invalid regular expression"                  // Status tooltip for regexp syntax that cannot be compiled.
    ui_NoMatch:                        string = "No match"                                    // Status line when a search reached the end with nothing.
    ui_Searching:                      string = "Searching…"                                  // Status line while a search scans the file.
    ui_DropTitle:                      string = "Drop a file to view it"                      // Invitation shown while no file is open.
    ui_DropHint:                       string = "or open one with Ctrl+O"                     // Secondary invitation shown while no file is open.
    ui_Unsupported:                    string = "No viewer can show this file."               // No viewer claimed the file.
    ui_OpenStopped:                    string = "The file could not be shown."                // A viewer refused the file it claimed.
    ui_ViewerError:                    string = "This viewer could not decode the file."      // Heading above a viewer's exact decoder error.
    ui_FailureNotFound:                string = "The file could not be found."                // A file that is gone, above the technical detail.
    ui_FailureUnreadable:              string = "The file could not be read."                 // A file the system or a decoder could not read, above the technical detail.
    ui_FailureFormat:                  string = "The file is damaged, or its format is not supported."     // A file whose content a decoder refused, above the technical detail.
    ui_AboutViewers:                   string = "Supported viewers"                           // Heading of the compact about block listing what the application opens.
    dlg_TitleOpen:                     string = "Open a file"                                 // Title of the open dialog.
    dlg_ButtonOpen:                    string = "Open"                                        // Confirmation button of the open dialog.
    dlg_AllFiles:                      string = "All files"                                   // Filter matching every extension.
}

private const FrenchStringsName = "lang/fr/scope.tweak"
private const FrenchStrings     = #include("../datas/lang/fr/scope.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of Swag Scope in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Registers the Swag Scope string table and its embedded translations.
//
// The resource is published before the table is registered: [[Gui.registerStrings]] translates a
// table only after it can find that table's translation file.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)

    // The file name here becomes `lang/<tag>/scope.tweak`, which must be the exact resource
    // name published above: a mismatch does not fail, it silently shows English.
    Gui.registerStrings'AppStrings(&g_AppStrings, "scope")
}

#run
{
    expect Gui.validateStrings'AppStrings(cast(string, FrenchStrings))
}
