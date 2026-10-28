#global public

using Core, Gui

// Visible strings of Swag Scope.
//
// The name of the application is a proper name and the name of an encoding is its standard
// spelling, so neither is translated wherever it appears inside one of these sentences.
struct AppStrings
{
    explore_Folders:           string = "Subfolders"                  // Sidebar navigation through the current location.
    explore_Back:              string = "Back"                        // Exploration control or status.
    explore_Forward:           string = "Forward"                     // Exploration control or status.
    explore_Up:                string = "Parent Folder"               // Exploration control or status.
    explore_Refresh:           string = "Refresh"                     // Exploration control or status.
    explore_Names:             string = "Names"                       // Exploration control or status.
    explore_Details:           string = "Details"                     // Exploration control or status.
    explore_Small:             string = "Small Thumbnails"            // Exploration control or status.
    explore_Medium:            string = "Medium Thumbnails"           // Exploration control or status.
    explore_Large:             string = "Large Thumbnails"            // Exploration control or status.
    explore_Name:              string = "Name"                        // Exploration control or status.
    explore_Type:              string = "Type"                        // Exploration control or status.
    explore_Size:              string = "Size"                        // Exploration control or status.
    explore_Modified:          string = "Modified"                    // Exploration control or status.
    explore_SelectFile:        string = "Select a file to see its information."
    explore_FileProperties:    string = "File"                       // Heading for local file properties.
    explore_MediaDetails:      string = "Media details"              // Heading for online media information.
    explore_Duration:          string = "Duration"
    explore_Released:          string = "Released"
    explore_Director:          string = "Director"
    explore_Cast:              string = "Cast"
    explore_Synopsis:          string = "Synopsis"
    explore_Artist:            string = "Artist"
    explore_FirstRelease:      string = "First release"
    explore_Source:            string = "Source"
    explore_Loading:           string = "Reading folder…"             // Exploration control or status.
    explore_Empty:             string = "No files to show"            // Exploration control or status.
    explore_OneItem:           string = "1 item"                      // Exploration control or status.
    explore_Count:             string = "% items"                     // Exploration control or status.
    explore_NotFound:          string = "Location not found"          // Exploration control or status.
    explore_MediaOptions:      string = "Online media options"
    explore_OnlineMovies:      string = "Use Online Movie Posters and Details"
    explore_ChooseMusic:       string = "Choose MusicBrainz Release Group ID…"
    explore_ChooseMusicHelp:   string = "Enter the release group ID from MusicBrainz. Leave empty to use automatic matching."
    explore_InvalidMusicId:    string = "Enter a valid MusicBrainz release group ID."
    explore_ChosenMusicFailed: string = "Could not load the chosen release. Check its MusicBrainz ID and your connection."
    explore_MovieDate:         string = "Released: %"
    explore_MovieOverview:     string = "Synopsis: %"
    explore_ImdbRating:        string = "IMDb rating via Wikidata: %"
    explore_MovieDirector:     string = "Director: %"
    explore_MovieCast:         string = "Cast: %"
    explore_OnlineMusic:       string = "Use Online Music Covers and Details"
    explore_MusicArtist:       string = "Artist: %"
    explore_MusicDate:         string = "First release: %"
    ui_AboutWikiNotice:        string = "Film information and summaries come from Wikipedia and Wikidata. Wikipedia text is available under CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/. Each film links to its source article."

    ui_OpenDefault:                    string = "Open with Default Application"               // Tooltip of the system-default application button.
    ui_CloseFile:                      string = "Close File"                                  // Tooltip of the close-file button.
    ui_Viewer:                         string = "Viewer"                                      // Tooltip of the viewer selector.
    ui_CloseFiles:                     string = "Close Files Panel"                           // Tooltip of the file-panel close button.
    ui_Files:                          string = "Files Beside This One"                       // Tooltip of the file-panel button.
    ui_SameKind:                       string = "Only Files of the Same Kind"                 // Tooltip of the folder-navigation filter toggle.
    ui_Options:                        string = "Options"                                     // Tooltip of the button opening the options of a viewer.
    ui_PlayMode:                       string = "Play mode"                                   // Tooltip of the play-mode button, and its row among the options.
    ui_PlayOnce:                       string = "Stop at the End"                             // Play-mode entry leaving a played file where it ended.
    ui_PlayRepeat:                     string = "Repeat the File"                             // Play-mode entry replaying the same file.
    ui_PlayFolder:                     string = "Play the Folder in Order"                    // Play-mode entry continuing with the next file of the same kind.
    ui_PlayShuffle:                    string = "Play the Folder Shuffled"                    // Play-mode entry continuing with a random file of the same kind.
    ui_PlaySlide:                      string = "Time per picture"                            // Option choosing how long a still picture stays.
    ui_Recent:                         string = "Recent"                                      // Panel section listing what was read before.
    ui_ClearHistory:                   string = "Clear History"                               // Tooltip of the clear-history button.
    ui_ConfirmClearHistory:            string = "The whole file history will be cleared."     // Consequence stated before confirming that the recent list is emptied.
    ui_Folder:                         string = "Folder"                                      // Panel section listing the current folder, before one is open.
    ui_FilterFiles:                    string = "Filter files by name"                        // Placeholder of the current-folder file filter.
    ui_FolderHistory:                  string = "Recent Folders"                              // Tooltip of the folder-history menu button.
    ui_MenuLocate:                     string = "Show This File in Its Folder"                // Panel menu entry selecting the file in the system file explorer.
    ui_MenuOpenDefault:                string = "Open with Default Application"               // File menu entry launching the registered system handler.
    ui_MenuOpenWith:                   string = "Open with Another Application…"              // Panel menu entry offering the system application chooser.
    ui_MenuCopyPath:                   string = "Copy Full Path"                              // Panel menu entry copying the complete file name.
    ui_MenuCopyName:                   string = "Copy File Name"                              // Panel menu entry copying the final path component.
    ui_MenuForget:                     string = "Remove This File from the History"           // Panel menu entry dropping one file from the recent list.
    ui_Search:                         string = "Find in document"                            // Placeholder of the search field.
    ui_SearchPrevious:                 string = "Previous Match (Shift+F3)"                   // Tooltip of the previous-match button.
    ui_SearchNext:                     string = "Next Match (F3)"                             // Tooltip of the next-match button.
    ui_SearchOptions:                  string = "Search Options"                              // Tooltip of the search-options menu button.
    ui_SearchMode:                     string = "Search"                                      // Shared query mode that finds occurrences.
    ui_FilterMode:                     string = "Filter"                                      // Shared query mode that limits visible viewer rows.
    ui_SearchMatchCase:                string = "Match Case"                                  // Search-options menu entry for case-sensitive matching.
    ui_SearchWholeWord:                string = "Match Whole Words"                           // Search-options menu entry for complete-word matching.
    ui_SearchRegularExpression:        string = "Use Regular Expression"                      // Search-options menu entry enabling regexp syntax.
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
    ui_HintLens:                       string = "everything else"                             // What the space bar opens, on the hint line of a window new to the reader.

    lens_File:          string = "File"                      // Lens section of the commands acting on the open file.
    lens_Find:          string = "Find"                      // Lens section of the search commands.
    lens_View:          string = "View"                      // Lens section of the presentation commands.
    lens_ViewAs:        string = "View As"                   // Lens section listing the viewers that can show the open file.
    lens_Playback:      string = "Playback"                  // Lens section of the play modes.
    lens_Folder:        string = "Folder"                    // Lens section of the commands of the explored folder.
    lens_InFolder:      string = "In This Folder"            // Lens section listing the files beside the open one.
    cmd_Open:           string = "Open…"                     // Command choosing a file to open.
    cmd_Explore:        string = "Explore Folder"            // Command showing the folder of the open file as a contact sheet.
    cmd_Reload:         string = "Reload"                    // Command reading the open file again.
    cmd_PreviousFile:   string = "Previous File"             // Command opening the file before this one in its folder.
    cmd_NextFile:       string = "Next File"                 // Command opening the file after this one in its folder.
    cmd_ClearHistory:   string = "Clear History…"            // Command emptying the list of recent files, after a confirmation.
    cmd_Find:           string = "Find in Document"          // Command showing the find bar.
    cmd_FindNext:       string = "Next Match"                // Command moving to the next occurrence.
    cmd_FindPrevious:   string = "Previous Match"            // Command moving to the previous occurrence.
    cmd_Information:    string = "Information"               // Command showing the sheet of readings about the open file.
    cmd_FullScreen:     string = "Full Screen"               // Command filling the monitor with the document.
    cmd_EditLocation:   string = "Type a Location"           // Command turning the explored path into a field.
    cmd_SortName:       string = "Sort by Name"              // Command ordering the explored folder by name.
    cmd_SortType:       string = "Sort by Type"              // Command ordering the explored folder by type.
    cmd_SortSize:       string = "Sort by Size"              // Command ordering the explored folder by size.
    cmd_SortModified:   string = "Sort by Date Modified"     // Command ordering the explored folder by modification date.
    cmd_SortDescending: string = "Descending Order"          // Command reversing the order of the explored folder.
    sort_Name:          string = "by name"                   // Quiet sort menu of the explored folder, ordered by name.
    sort_Type:          string = "by type"                   // Quiet sort menu of the explored folder, ordered by type.
    sort_Size:          string = "by size"                   // Quiet sort menu of the explored folder, ordered by size.
    sort_Modified:      string = "by date"                   // Quiet sort menu of the explored folder, ordered by date.

    dlg_TitleOpen:                     string = "Open a File"                                 // Title of the open dialog.
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
