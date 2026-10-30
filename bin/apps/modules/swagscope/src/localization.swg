#global public

using Core, Gui

// Visible strings of Swag Scope.
//
// The name of the application is a proper name and the name of an encoding is its standard
// spelling, so neither is translated wherever it appears inside one of these sentences.
struct AppStrings
{
    // Alternative phrases for command discovery; semicolons separate complete phrases.
    search_Open:       string = "open movie;open video;open image"
    search_Browse:     string = "browse library;browse folder;media library"
    search_FullScreen: string = "cinema;fullscreen"

    explore_Folders:           string = "Subfolders"            // Sidebar navigation through the current location.
    explore_Back:              string = "Back"                  // Exploration control or status.
    explore_Forward:           string = "Forward"               // Exploration control or status.
    explore_Up:                string = "Parent Folder"         // Exploration control or status.
    explore_Refresh:           string = "Refresh"               // Exploration control or status.
    explore_Names:             string = "Names"                 // Exploration control or status.
    explore_Details:           string = "Details"               // Exploration control or status.
    explore_Small:             string = "Small Thumbnails"      // Exploration control or status.
    explore_Medium:            string = "Medium Thumbnails"     // Exploration control or status.
    explore_Large:             string = "Large Thumbnails"      // Exploration control or status.
    explore_Name:              string = "Name"                  // Exploration control or status.
    explore_Type:              string = "Type"                  // Exploration control or status.
    explore_Size:              string = "Size"                  // Exploration control or status.
    explore_Modified:          string = "Modified"              // Exploration control or status.
    explore_SelectFile:        string = "Select a file to see its information."
    explore_FileProperties:    string = "File"     // Heading for local file properties.
    explore_MediaDetails:      string = "Media details"     // Heading for online media information.
    explore_Duration:          string = "Duration"
    explore_Released:          string = "Released"
    explore_Director:          string = "Director"
    explore_Cast:              string = "Cast"
    explore_Synopsis:          string = "Synopsis"
    explore_Length:            string = "% h %"          // Length of a film under its poster: hours, then minutes.
    explore_Sources:           string = "Sources"        // Reading naming who provided what the sheet says of a film.
    explore_OnePage:           string = "1 page"         // Facts of a document of one page under its cell.
    explore_Pages:             string = "% pages"        // Facts of a document under its cell: its pages.
    explore_Lines:             string = "% lines"        // Facts of a text or code file under its cell: its lines.
    explore_Sections:          string = "% sections"     // Facts of a Markdown file under its cell: its sections.
    explore_Files:             string = "% files"        // Facts of an archive under its cell: the files it holds.
    explore_Albums:            string = "% albums"       // How many albums a music library holds.
    explore_Photos:            string = "% photos"       // How many pictures a folder of photographs holds.
    explore_Album:             string = "Album"          // Kind of the folder an album page shows, before its year.
    explore_Tracks:            string = "% tracks"       // How many tracks an album holds.
    explore_Play:              string = "Play"           // Button playing an album from its first track.
    explore_Shuffle:           string = "Shuffle"        // Button playing an album in an order drawn by chance.
    explore_Weekdays:          string = "Sunday Monday Tuesday Wednesday Thursday Friday Saturday"     // Days of a mosaic of pictures, from Sunday, separated by spaces.
    explore_Months:            string = "January February March April May June July August September October November December"     // Months of a mosaic of pictures, separated by spaces.
    explore_File:              string = "File"           // Reading of the kind and weight of the file a film is in.
    explore_Artist:            string = "Artist"
    explore_FirstRelease:      string = "First release"
    explore_Source:            string = "Source"
    explore_FileTags:          string = "File tags"
    explore_Loading:           string = "Reading folder…"                         // Exploration control or status.
    explore_Empty:             string = "No files to show"                        // Exploration control or status.
    explore_NoMatches:         string = "No files match this filter."              // Empty filtered folder.
    explore_OneItem:           string = "1 item"                                  // Exploration control or status.
    explore_Count:             string = "% items"                                 // Exploration control or status.
    explore_ArchiveSummary:    string = "% · % compressed · % once extracted"     // Contents of an archive: its count, its packed and its extracted weight.
    explore_Compression:       string = "Compression"                             // Reading of how much an archive member packed.
    explore_Extracted:         string = "% files extracted"                       // Toast after an extraction from an archive.
    explore_ExtractedOne:      string = "1 file extracted"                        // Toast after extracting one file from an archive.
    explore_ExtractedKept:     string = "%, % already there kept"                 // Toast after an extraction that left files already in the folder as they were.
    explore_ExtractFailed:     string = "Not everything could be extracted"       // Toast when an extraction stopped on an error.
    explore_NotFound:          string = "Location not found"                      // Exploration control or status.
    explore_MediaOptions:      string = "Online Media Options"
    ui_GeneralOptions:         string = "General Options…"
    ui_GeneralOptionsTitle:    string = "Options"
    ui_SaveOptions:            string = "Save Options"
    options_OnlineMovieHelp:   string = "TMDB first, then Apple and Wikipedia."
    options_DocumentTheme:     string = "Document Theme"
    options_ReadingWidth:      string = "Reading Width"
    options_Zoom:              string = "Zoom"
    options_PitchLabels:       string = "Pitch Labels"
    options_KeyboardWidth:     string = "Keyboard Width"
    options_SubtitleFont:      string = "Subtitle Font"
    options_SubtitleSize:      string = "Subtitle Size"
    options_SubtitleEffect:    string = "Subtitle Effect"
    options_SubtitlePosition:  string = "Subtitle Position"
    options_SubtitleColor:     string = "Subtitle Color"
    options_SubtitleDelay:     string = "Subtitle Delay"
    ui_TMDBToken:              string = "TMDB Read Access Token"
    ui_TMDBKey:                string = "TMDB API Key"
    ui_TMDBTokenHelp:          string = "Leave empty to keep the saved token. TMDB is the first movie source."
    ui_TMDBKeyHelp:            string = "Leave empty to keep the saved key. It is used when no token is available."
    ui_TMDBClear:              string = "Remove Saved TMDB Credentials"
    ui_TMDBClearHelp:          string = "The token and key are stored only in this computer's Swag Scope settings."
    ui_OnlineMusicHelp:        string = "MusicBrainz and Cover Art Archive do not need an API key."
    ui_InvalidTMDBToken:       string = "Enter a valid TMDB read access token."
    ui_InvalidTMDBKey:         string = "Enter a 32-character hexadecimal TMDB API key."
    ui_SaveMediaOptionsFailed: string = "Could not save the online media options."
    explore_OnlineMovies:      string = "Use Online Movie Posters and Details"
    explore_ChooseMusic:       string = "Choose MusicBrainz Release Group ID…"
    explore_ChooseMusicHelp:   string = "Enter the release group ID from MusicBrainz. Leave empty to use automatic matching."
    explore_InvalidMusicId:    string = "Enter a valid MusicBrainz release group ID."
    explore_ChosenMusicFailed: string = "Could not load the chosen release. Check its MusicBrainz ID and your connection."
    explore_MovieDate:         string = "Released: %"
    explore_MovieOverview:     string = "Synopsis: %"
    explore_ImdbRating:        string = "IMDb rating via Wikidata: %"
    explore_TmdbRating:        string = "TMDB rating: %"
    explore_MovieDirector:     string = "Director: %"
    explore_MovieCast:         string = "Cast: %"
    explore_OnlineMusic:       string = "Use Online Music Covers and Details"
    explore_MusicArtist:       string = "Artist: %"
    explore_MusicDate:         string = "First release: %"
    ui_AboutWikiNotice:        string = "This product uses the TMDB API but is not endorsed or certified by TMDB. TMDB supplies film posters, summaries and ratings. Apple, then Wikipedia and Wikidata, provide fallback information. Wikipedia text is available under CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/."

    ui_OpenDefault:                    string = "Open with Default Application"               // Tooltip of the system-default application button.
    ui_CloseFile:                      string = "Close File"                                  // Tooltip of the close-file button.
    ui_Viewer:                         string = "Viewer"                                      // Tooltip of the viewer selector.
    ui_CloseFiles:                     string = "Close Files Panel"                           // Tooltip of the file-panel close button.
    ui_Files:                          string = "Files Beside This One"                       // Tooltip of the file-panel button.
    ui_SameKind:                       string = "Only Files of the Same Kind"                 // Tooltip of the folder-navigation filter toggle.
    ui_Options:                        string = "Options"                                     // Tooltip of the button opening the options of a viewer.
    ui_PlayMode:                       string = "Play Mode"                                   // Tooltip of the play-mode button, and its row among the options.
    ui_PlayOnce:                       string = "Stop at the End"                             // Play-mode entry leaving a played file where it ended.
    ui_PlayRepeat:                     string = "Repeat the File"                             // Play-mode entry replaying the same file.
    ui_PlayFolder:                     string = "Play the Folder in Order"                    // Play-mode entry continuing with the next file of the same kind.
    ui_PlayShuffle:                    string = "Play the Folder Shuffled"                    // Play-mode entry continuing with a random file of the same kind.
    ui_PlaySlide:                      string = "Time per Picture"                            // Option choosing how long a still picture stays.
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
    ui_SearchPrevious:                 string = "Previous Match (Shift F3)"                   // Tooltip of the previous-match button.
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
    home_Invite:                       string = "Drop a file, or open one"                    // File invitation on the home page; the key follows it.
    home_InviteFolder:                 string = "Open a folder"                               // Folder invitation on the home page; the key follows it.
    home_Clear:                        string = "Clear…"                                      // Quiet command under the last files, opening the clears.
    home_ClearMissing:                 string = "Remove Missing Files"                        // Clear of the history entries whose file is gone.
    home_MissingTitle:                 string = "File not found."                              // Title of the question after a recent file is missing.
    home_AskForgetMissing:             string = "Remove it from the file history?"            // Question offering to drop the missing file from the history.
    home_ClearOlder:                   string = "Older Than a Month"                          // Clear of the history entries last opened more than a month ago.
    home_ClearAll:                     string = "Clear All…"                                  // Clear of the whole history, after a question.
    home_Yesterday:                    string = "yesterday"                                   // When a file was last opened, the day before today.
    home_Weekdays:                     string = "Sun Mon Tue Wed Thu Fri Sat"                 // When a file was last opened this week, from Sunday, separated by spaces.
    ui_Unsupported:                    string = "No viewer can show this file."               // No viewer claimed the file.
    ui_OpenStopped:                    string = "The file could not be shown."                // A viewer refused the file it claimed.
    ui_ViewerError:                    string = "This viewer could not decode the file."      // Heading above a viewer's exact decoder error.
    ui_FailureNotFound:                string = "The file could not be found."                // A file that is gone, above the technical detail.
    ui_FailureUnreadable:              string = "The file could not be read."                 // A file the system or a decoder could not read, above the technical detail.
    ui_FailureFormat:                  string = "The file is damaged, or its format is not supported."     // A file whose content a decoder refused, above the technical detail.
    ui_AboutViewers:                   string = "Supported viewers"                           // Heading of the compact about block listing what the application opens.
    hint_KeyBack:                      string = "⌫"                                           // Name of the Backspace key on a keycap.
    hint_Open:                         string = "open"                                        // What Enter does on the hint line of an explored folder.
    hint_Parent:                       string = "parent folder"                               // What Backspace does on the hint line of an explored folder.
    hint_PlayAlbum:                    string = "play the album"                              // What P does on the hint line of a music library.
    hint_Play:                         string = "play"                                        // What Enter does on the hint line of an album.
    hint_Filter:                       string = "filter"                                      // What the slash key does on the hint line of an explored folder.
    ui_HintLens:                       string = "everything else"                             // What Ctrl Space opens, on the hint line of a window new to the reader.

    lens_File:          string = "File"                      // Lens section of the commands acting on the open file.
    lens_Find:          string = "Find"                      // Lens section of the search commands.
    lens_View:          string = "View"                      // Lens section of the presentation commands.
    lens_ViewAs:        string = "View As"                   // Lens section listing the viewers that can show the open file.
    lens_Playback:      string = "Playback"                  // Lens section of the play modes.
    lens_Folder:        string = "Folder"                    // Lens section of the commands of the explored folder.
    lens_InFolder:      string = "In This Folder"            // Lens section listing the files beside the open one.
    lens_InFile:        string = "In This File"              // Lens section listing the lines of the open file that hold the query.
    lens_GoToLine:      string = "Go to Line %"              // Lens row going to the line typed after a colon.
    cmd_Open:           string = "Open…"                     // Command choosing a file to open.
    cmd_OpenChosen:     string = "Open"                      // Command opening the item chosen in the explored folder.
    cmd_ExtractAll:     string = "Extract All…"              // Command extracting the whole explored archive to a folder.
    cmd_Extract:        string = "Extract…"                  // Command extracting the chosen member or folder of the archive to a folder.
    cmd_Explore:        string = "Explore Folder"            // Command showing the folder of the open file as a contact sheet.
    cmd_Reload:         string = "Reload"                    // Command reading the open file again.
    cmd_PreviousFile:   string = "Previous File"             // Command opening the file before this one in its folder.
    cmd_NextFile:       string = "Next File"                 // Command opening the file after this one in its folder.
    cmd_ClearHistory:   string = "Clear History…"            // Command emptying the list of recent files, after a confirmation.
    cmd_Find:           string = "Find in Document"          // Command showing the find bar.
    cmd_FilterFiles:    string = "Filter Files"              // Command showing the folder filter.
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
    cmd_Options:        string = "Options…"                  // Command opening the options sheet of the viewer.
    cmd_Play:           string = "Play"                      // Command starting playback.
    cmd_Pause:          string = "Pause"                     // Command pausing playback.
    cmd_Stop:           string = "Stop"                      // Command stopping playback and going back to the start.
    cmd_SeekBackward:   string = "Back 10 Seconds"           // Command moving playback back by ten seconds.
    cmd_SeekForward:    string = "Forward 10 Seconds"        // Command moving playback forward by ten seconds.
    cmd_PreviousFrame:  string = "Previous Frame"            // Command stepping a film back by one picture.
    cmd_NextFrame:      string = "Next Frame"                // Command stepping a film forward by one picture.
    cmd_Mute:           string = "Mute"                      // Command silencing playback; checked while it is silent.
    cmd_PlayMode:       string = "Play Mode…"                // Command opening the play mode sheet.
    cmd_ZoomIn:         string = "Zoom In"                   // Command enlarging the document by one notch.
    cmd_ZoomOut:        string = "Zoom Out"                  // Command reducing the document by one notch.
    cmd_ZoomReset:      string = "Actual Size"               // Command showing the document at its own size.
    cmd_ZoomMenu:       string = "Zoom…"                     // Command opening the zoom levels of the viewer.
    mode_Names:         string = "names"                     // Quiet view menu of the explored folder, as a list of names.
    mode_Details:       string = "details"                   // Quiet view menu of the explored folder, as a table of details.
    mode_Thumbnails:    string = "thumbnails"                // Quiet view menu of the explored folder, as a contact sheet.
    mode_Covers:        string = "covers"                    // Quiet view menu of the explored folder, as album covers.
    mode_Posters:       string = "posters"                   // Quiet view menu of the explored folder, as film posters.
    mode_Mosaic:        string = "mosaic"                    // Quiet view menu of the explored folder, as a mosaic of pictures.
    board_Automatic:    string = "Automatic"                 // View menu choice reading the shape of the tiles from what the folder holds.
    board_Grid:         string = "Grid"                      // View menu choice forcing an even grid of tiles.
    board_Covers:       string = "Covers"                    // View menu choice forcing square covers.
    board_Posters:      string = "Posters"                   // View menu choice forcing upright posters.
    board_Mosaic:       string = "Mosaic"                    // View menu choice forcing a mosaic of pictures.
    sort_Name:          string = "by name"                   // Quiet sort menu of the explored folder, ordered by name.
    sort_Type:          string = "by type"                   // Quiet sort menu of the explored folder, ordered by type.
    sort_Size:          string = "by size"                   // Quiet sort menu of the explored folder, ordered by size.
    sort_Modified:      string = "by date"                   // Quiet sort menu of the explored folder, ordered by date.

    dlg_TitleOpen:  string = "Open a File"     // Title of the open dialog.
    dlg_ButtonOpen: string = "Open"            // Confirmation button of the open dialog.
    dlg_AllFiles:   string = "All Files"       // Filter matching every extension.
}

private const FrenchStringsName = "lang/fr/scope.tweak"
private const FrenchStrings     = #include("../datas/lang/fr/scope.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of Swag Scope in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Resolves the property page's compile-time field names in the current language.
private func resolveScopePropertyText(key: string)->string?
{
    let texts = appStrings()
    switch key
    {
    case "Online Movie Posters and Details": return texts.explore_OnlineMovies
    case "Online Music Covers and Details": return texts.explore_OnlineMusic
    case "TMDB first, then Apple and Wikipedia.": return texts.options_OnlineMovieHelp
    case "MusicBrainz and Cover Art Archive need no API key.": return texts.ui_OnlineMusicHelp
    case "TMDB Read Access Token": return texts.ui_TMDBToken
    case "TMDB API Key": return texts.ui_TMDBKey
    case "Paste a new token, or leave empty to keep the saved one. TMDB is the first movie source.": return texts.ui_TMDBTokenHelp
    case "Paste a new key, or leave empty to keep the saved one. Used only without a token.": return texts.ui_TMDBKeyHelp
    case "Remove Saved TMDB Credentials": return texts.ui_TMDBClear
    case "Remove the local token and key when this page closes.": return texts.ui_TMDBClearHelp
    case "Document Theme": return texts.options_DocumentTheme
    case "Reading Width": return texts.options_ReadingWidth
    case "Zoom": return texts.options_Zoom
    case "Pitch Labels": return texts.options_PitchLabels
    case "Keyboard Width": return texts.options_KeyboardWidth
    case "Subtitle Font": return texts.options_SubtitleFont
    case "Subtitle Size": return texts.options_SubtitleSize
    case "Subtitle Effect": return texts.options_SubtitleEffect
    case "Subtitle Position": return texts.options_SubtitlePosition
    case "Subtitle Color": return texts.options_SubtitleColor
    case "Subtitle Delay": return texts.options_SubtitleDelay
    default: return null
    }
}

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
    Gui.Properties.setTextResolver(&resolveScopePropertyText)
}

#run
{
    expect Gui.validateStrings'AppStrings(cast(string, FrenchStrings))
}
