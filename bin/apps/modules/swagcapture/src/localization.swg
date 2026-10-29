#global public

using Core, Gui

// Visible strings of Swag Capture.
//
// The declared values are the reference English wording, and each field is one
// translatable key. Translations live in `datas/lang/<tag>/capture.tweak`; a key a
// language file omits keeps its reference value. Read the active table through
// [[appStrings]]; never keep a copy across a language switch.
struct AppStrings
{
    ui_MenuFile:                string = "File"
    ui_MenuCapture:             string = "Capture"
    ui_MenuEdit:                string = "Edit"
    ui_MenuImage:               string = "Image"
    ui_MenuView:                string = "View"
    ui_MenuAlign:               string = "Align"
    ui_MenuArrange:             string = "Arrange"
    ui_AllCaptures:             string = "All Items"
    ui_ImageBadge:              string = "IMAGE"
    ui_CommaSeparatedTags:      string = "Tags separated by commas"
    ui_Search:                  string = "Search"
    ui_BarView:                 string = "View"
    ui_Overlays:                string = "Overlays"
    ui_ThumbnailSize:           string = "Thumbnail size"     // Option choosing how large the thumbnails of the library are.
    ui_SortBy:                  string = "Sort by"            // Option choosing the order of the library.
    ui_FilterContent:           string = "Content"            // Filter on what kind of item the library shows.
    ui_FilterRating:            string = "Rating"             // Filter on the rating of the captures.
    ui_FilterLinks:             string = "Linked images"      // Filters on the state of the images linked to captures.
    ui_BarFilter:               string = "Filter"
    ui_BarFolders:              string = "Folders"
    ui_RenameQuickStyle:        string = "Rename Quick Style…"         // Names a quick style.
    ui_ReplaceQuickStyle:       string = "Replace with Current Style"  // Gives a quick style the style of the tool or the selection.
    ui_QuickStyleRank:          string = "Style %"                     // Name of a quick style the reader has not named, with its rank.
    ui_QuickStyleCaption:       string = "Quick style “%” · right-click to rename, replace or remove it"     // Under the quick styles: the one in force.
    ui_QuickStyleName:          string = "Name of the quick style"     // Prompt of the quick-style rename dialog.
    dlg_TitleRenameQuickStyle:  string = "Rename Quick Style"          // Title of the quick-style rename dialog.
    ui_RemoveQuickStyle:        string = "Remove Quick Style"
    ui_SectionEditor:           string = "Editor"
    ui_SectionApplication:      string = "Application"
    ui_DetailFile:              string = "<b>File</b>"
    ui_DetailLinkedImage:       string = "<b>Linked Image</b>"
    ui_DetailImageSize:         string = "<b>Image Size</b>"
    ui_DetailCapturedAt:        string = "<b>Captured</b>"
    ui_DetailApplication:       string = "<b>Application</b>"
    ui_DetailWindowTitle:       string = "<b>Window</b>"
    ui_DetailExecutable:        string = "<b>Executable</b>"
    ui_DetailWindowClass:       string = "<b>Window Class</b>"
    ui_DetailTags:              string = "<b>Tags</b>"
    ui_DetailRating:            string = "<b>Rating</b>"
    ui_DetailFileSize:          string = "<b>File Size</b>"
    ui_Width:                   string = "Width"
    ui_Height:                  string = "Height"
    ui_KeepRatio:               string = "Keep Ratio"
    ui_Anchor:                  string = "Anchor"
    ui_Frozen:                  string = "Selection is frozen"
    ui_Desktop:                 string = "Desktop"
    ui_MyImages:                string = "My Images"
    ui_CommonImages:            string = "Images"
    dlg_TitleOptions:           string = "Options"
    dlg_TitleDetails:           string = "Details"
    dlg_TitleLoadImage:         string = "Load Image"
    dlg_TitleSaveAsImage:       string = "Save as Image"
    dlg_TitleChooseLibrary:     string = "Choose Library Folder"
    dlg_TitleBrowseFolder:      string = "Browse Image Folder"
    dlg_TitleEditTags:          string = "Edit Tags"
    dlg_TitleExportCaptures:    string = "Export Captures"
    dlg_TitleResizeImage:       string = "Resize Image"
    dlg_TitleExpandImage:       string = "Expand Image"
    dlg_TitleExpandCapture:     string = "Expand Capture"
    dlg_BtnCreate:              string = "Create"
    dlg_BtnResize:              string = "Resize"
    dlg_BtnLoad:                string = "Load"
    dlg_BtnSave:                string = "Save"
    dlg_BtnExport:              string = "Export"
    msg_RemoveAssociation:      string = "This will remove the image association."
    msg_DeleteCaptures:         string = "This will delete the capture file(s)."
    msg_EraseTrash:             string = "This will permanently erase every capture in the recycle bin."
    msg_EraseSelected:          string = "This will permanently erase the selected capture(s)."
    msg_OverwriteLinked:        string = "This will overwrite the original image."     // Confirmation before updating a linked image.
    ui_DoNotAskAgain:           string = "Do not ask again"     // Option of a confirmation that turns it off.
    ui_CaptureName:             string = "Capture name"         // Field of the capture rename dialog.
    msg_FailedDuplicate:        string = "Failed to duplicate capture"
    msg_FailedLocateCapture:    string = "Failed to locate capture file"
    msg_FailedLocateLinked:     string = "Failed to locate linked image"
    msg_FailedLoadImage:        string = "Failed to load image"
    msg_FailedSaveFile:         string = "Failed to save file"
    msg_FailedSaveCapture:      string = "Failed to save capture file: %"
    msg_FailedRename:           string = "Failed to rename capture"
    msg_FailedCopyImage:        string = "Failed to copy image"
    msg_Saved:                  string = "Saved"                       // Toast after an image was written to a file, with its name.
    msg_Copied:                 string = "Copied to the clipboard"     // Toast after an image was copied.
    msg_Pinned:                 string = "Pinned on the screen"        // Toast after a capture was pinned on the screen.
    act_Show:                   string = "Show"                        // Action of the saved toast: shows the file in its folder.
    act_Pin:                    string = "Pin"                         // Pins the capture on the screen, from the in-place editor.
    act_InpEditor:              string = "Editor"                      // Opens the capture in the editor, from the in-place editor.
    act_InpSave:                string = "Save…"                       // Saves the capture as an image file, from the in-place editor.
    act_InpCopy:                string = "Copy"                        // Copies the capture and closes the in-place editor.
    hint_CopyClose:             string = "copy and close"              // What Enter does in the in-place editor.
    hint_Save:                  string = "save"                        // What Ctrl+S does in the in-place editor.
    hint_CalloutTail:           string = "Drag the point of the tail to aim it"     // Hint while the words of a callout are typed in place.
    hint_NewLine:               string = "new line"                    // What Enter does while the words of a form are typed in place.
    hint_KeepText:              string = "keep the text"               // What Ctrl+Enter does while the words of a form are typed in place.
    ui_Common:                  string = "Common"                      // Section of the inspector holding what several objects share.
    ui_NoColor:                 string = "none"                        // Value of a colour row whose colour is fully transparent.
    msg_FailedCaptureScreen:    string = "Failed to capture the screen"
    msg_FailedLoadFile:         string = "Failed to load file: %"
    msg_FailedOpenLibrary:      string = "Cannot open the library folder"
    msg_FailedSaveMetadata:     string = "Cannot save capture metadata"
    msg_FailedExportCaptures:   string = "Cannot export the selected captures"
    msg_ShortcutTaken:          string = "Cannot register global shortcut '%'. "
    msg_ShortcutTakenWhy:       string = "Another running application is probably already using it!"
    msg_ShortcutsTaken:         string = "Cannot register global shortcuts %. "     // Lists every unavailable shortcut, each one quoted.
    msg_ShortcutsTakenWhy:      string = "Other running applications are probably already using them!"
    msg_ResetStyles:            string = "This will reset the styles to the default values."     // Confirmation before restoring the default quick styles.
    dlg_TitleRenameCapture:     string = "Rename Capture"              // Title of the capture rename dialog.
    ui_Outline:                 string = "Outline"                     // Label of the outline thickness slider.
    ui_PropFill:                string = "Fill"                        // Fill color swatch of the tool panel.
    ui_PropOutline:             string = "Outline"                     // Outline color swatch of the tool panel.
    ui_PropColor:               string = "Color"                       // Stroke color swatch, for the forms that have no fill.
    ui_PropStart:               string = "Start"                       // Start cap of a line or an arrow.
    ui_PropEnd:                 string = "End"                         // End cap of a line or an arrow.
    ui_PropDash:                string = "Dash"                        // Dash pattern of a stroke.
    ui_PropStyle:               string = "Style"                       // Section of the glyph choices: the kind of a shape, its dashes, the ends of a line.
    ui_PropPosition:            string = "Position"                    // Category of the position and size rows.
    ui_PropSize:                string = "Size"                        // Size row of the position category.
    ui_ResetSteps:              string = "Reset"                       // Restarts the numbered-step counter.
    ui_OneObject:               string = "1 object"                    // Detail of the inspector title when one object is selected.
    ui_Objects:                 string = "% objects"                   // Inspector title when several objects are selected, with their count.
    ui_NextObjects:             string = "next objects"                // Detail of the inspector title when nothing is selected: the tool's settings apply to what is drawn next.
    hint_Space:                 string = "capture, open, library"      // What the Space key opens, on the hint line of the editor.
    hint_LibrarySpace:          string = "export, tag, rate, move"     // What the Space key opens, on the hint line of the library.
    ui_LibraryEmpty:            string = "No captures here yet."       // Sentence of a library folder that holds nothing.
    ui_LibraryNoMatch:          string = "No capture matches the filters or the search."     // Sentence of a library page the filters emptied.
    lens_Tools:                 string = "Tools"                       // Lens section of the drawing tools.
    lens_Recent:                string = "Recent"                      // Lens section of the recent captures.
    lens_Selection:             string = "Selection"                   // Lens section of the actions of the selected shapes, at rest.
    lens_LibraryLink:           string = "Library →"                   // Link ending the recent captures of the lens: opens the library.
    lens_Dates:                 string = "Dates"                       // Lens section of the dates the library can be narrowed to.
    ui_ModeArea:                string = "Area"                        // Capture mode of the area overlay: the zone the reader draws.
    ui_ModeActiveWindow:        string = "Active Window"               // Capture mode of the area overlay: the window in front.
    ui_ModeFullScreen:          string = "Full Screen"                 // Capture mode of the area overlay: every screen.
    ui_ModeLastArea:            string = "Last Area"                   // Capture mode of the area overlay: the zone of the previous capture.
    hint_Capture:               string = "capture"                     // What Enter does on the area overlay.
    ui_Delay:                   string = "Delay: %"                    // How long the area overlay waits before reading the screen, with that delay.
    ui_DelayNone:               string = "none"                        // No delay before the screen is read.
    ui_DelaySeconds:            string = "% s"                         // A delay before the screen is read, in seconds.
    ui_Cursor:                  string = "Cursor"                      // Switch of the area overlay: whether the screen is read with the cursor.
    hint_Cancel:                string = "cancel"                      // What Escape does on the area overlay.
    act_OpenLens:               string = "Search Commands"             // Opens the lens.
    act_ShowInspector:          string = "Properties"                  // Folds or unfolds the inspector.
    act_ShowRecent:             string = "Recent Captures"             // Shows or hides the strip of recent captures.
    act_ResetSteps:             string = "Reset Step Numbers"          // Restarts the numbering of the step markers at 1.
    tip_AllQuickStyles:         string = "All Styles"                  // The chip opening every quick style of the tool.
    tip_AddQuickStyle:          string = "Keep the current style as a quick style"     // The chip after the quick styles of the inspector.
    ui_RecentColors:            string = "Recent"                      // Section of the colour popover: the colours used last.
    ui_Palette:                 string = "Palette"                     // Section of the colour popover: the palette.
    ui_Layers:                  string = "Layers"                      // Section of the inspector listing the objects of the capture.
    ui_PosX:                    string = "X"                           // Letter of the horizontal position of an object.
    ui_PosY:                    string = "Y"                           // Letter of the vertical position of an object.
    ui_PosW:                    string = "W"                           // Letter of the width of an object.
    ui_PosH:                    string = "H"                           // Letter of the height of an object.
    hint_AllProperties:         string = "all properties"              // What the key of the folded inspector opens, on the hint line.
    hint_ToolSelect:            string = "Click an object to choose it, drag around several"        // Hint of the selection tool.
    hint_ToolShape:             string = "Drag to draw a rectangle or an ellipse"                     // Hint of the shape tool.
    hint_ToolArrow:             string = "Drag to draw an arrow"                                      // Hint of the arrow tool.
    hint_ToolLine:              string = "Drag to draw a line"                                        // Hint of the line tool.
    hint_ToolPolygon:           string = "Drag to draw a polygon"                                     // Hint of the polygon tool.
    hint_ToolText:              string = "Drag to place a text"                                       // Hint of the text tool.
    hint_ToolCallout:           string = "Drag to place a callout, then drag the point of its tail to aim it"     // Hint of the callout tool.
    hint_ToolDraw:              string = "Drag to draw freehand"                                      // Hint of the drawing tool.
    hint_ToolHighlight:         string = "Drag over what to highlight"                                // Hint of the highlight tool.
    hint_ToolImage:             string = "Drag to place a picture or an effect"                       // Hint of the image tool.
    hint_ToolPixSel:            string = "Drag to choose pixels"                                      // Hint of the pixel selection tool.
    hint_ToolFavorites:         string = "Pick a style, then drag to draw it"                         // Hint of the favorites tool.
    hint_ToolStep:              string = "The next click places %"                                    // Hint of the step tool, with the next number.
    act_CaptureMonitor:         string = "Capture Monitor %"           // Capture one monitor, by index.
    act_CaptureMonitorSize:     string = "Capture Monitor % (%x%)"     // Capture one monitor, with its size.
    act_ActualSize:             string = "Actual Size"
    act_Arrow:                  string = "Arrow"
    act_BigView:                string = "Big View"
    act_Callout:                string = "Callout"
    act_CaptureActiveWindow:    string = "Capture Active Window"
    act_CaptureArea:            string = "Capture Area"
    act_CaptureFullScreen:      string = "Capture Full Screen"
    act_CaptureLastArea:        string = "Capture Last Area"
    act_CaptureCursor:          string = "Capture Mouse Cursor"
    act_Clear:                  string = "Clear"
    act_ClearInsideImage:       string = "Clear Inside Image"
    act_CopyImageToClipboard:   string = "Copy Image to Clipboard"
    act_Copy:                   string = "Copy"
    act_Cut:                    string = "Cut"
    act_Delay1:                 string = "Delay Before Capture (1 Second)"
    act_Delay2:                 string = "Delay Before Capture (2 Seconds)"
    act_Delay5:                 string = "Delay Before Capture (5 Seconds)"
    act_Delay9:                 string = "Delay Before Capture (9 Seconds)"
    act_DelayBefore:            string = "Delay Before Capture"
    act_OneSecond:              string = "1 Second"
    act_TwoSeconds:             string = "2 Seconds"
    act_FiveSeconds:            string = "5 Seconds"
    act_NineSeconds:            string = "9 Seconds"
    act_NoDelay:                string = "No Delay"
    act_DeletePermanently:      string = "Delete Permanently"
    act_Delete:                 string = "Delete"
    act_DeselectAll:            string = "Deselect All Objects"
    act_FilterNoLinked:         string = "Doesn't Have Linked Image"
    act_ExpandCapture:          string = "Expand Capture…"
    act_ExpandImage:            string = "Expand Image…"
    act_Draw:                   string = "Draw"
    act_Duplicate:              string = "Duplicate"
    act_EditInPlace:            string = "Edit Captured Area in Place"
    act_EmptyRecycleBin:        string = "Empty Recycle Bin"
    act_Favorites:              string = "Favorites"
    act_Fill:                   string = "Fill"
    act_FileDetails:            string = "File Details"
    act_OpenSelected:           string = "Open"
    act_LocateImage:            string = "Show Image in Folder"
    act_EditTags:               string = "Edit Tags…"
    act_ExportSelected:         string = "Export Selected…"
    act_FavoriteCapture:        string = "Favorite"
    act_Rating:                 string = "Rating"
    act_NoRating:               string = "No Rating"
    act_Rating1:                string = "1 Star"
    act_Rating2:                string = "2 Stars"
    act_Rating3:                string = "3 Stars"
    act_Rating4:                string = "4 Stars"
    act_Rating5:                string = "5 Stars"
    act_ShowRatings:            string = "Ratings"
    act_ShowLinkMarkers:        string = "Link Markers"
    act_BrowseFolder:           string = "Browse Folder…"
    act_OpenLibraryFolder:      string = "Open Library Folder"
    act_ChooseLibraryFolder:    string = "Use Another Library Folder…"
    act_UseDefaultLibrary:      string = "Use Default Library Folder"
    act_Application:            string = "Application"
    act_AllApplications:        string = "All Applications"
    act_Tags:                   string = "Tags"
    act_AllTags:                string = "All Tags"
    act_ResetFilters:           string = "Clear Filters"
    act_FilterAllItems:         string = "All Items"
    act_FilterCaptures:         string = "Captures"
    act_FilterScreenCaptures:   string = "Screen Captures"
    act_FilterImportedCaptures: string = "Imported Captures"
    act_FilterImages:           string = "External Images"
    act_FilterFavorites:        string = "Favorites Only"
    act_FilterAnyRating:        string = "Any Rating"
    act_FilterRating1:          string = "At Least 1 Star"
    act_FilterRating2:          string = "At Least 2 Stars"
    act_FilterRating3:          string = "At Least 3 Stars"
    act_FilterRating4:          string = "At Least 4 Stars"
    act_FilterRating5:          string = "5 Stars"
    act_SortCapturedAt:         string = "Capture Time"
    act_SortModified:           string = "Modified Time"
    act_SortName:               string = "Name"
    act_SortApplication:        string = "Application"
    act_SortWindowTitle:        string = "Window Title"
    act_SortDimensions:         string = "Image Dimensions"
    act_SmallerImagesFirst:     string = "Smaller Images First"
    act_SortFileSize:           string = "File Size"
    act_FitToView:              string = "Fit to View"
    act_Flatten:                string = "Flatten"
    act_FlattenAll:             string = "Flatten All"
    act_FlipImage:              string = "Flip Image"
    act_FreezeSelection:        string = "Freeze Selection"
    act_Group:                  string = "Group"
    act_MirrorImage:            string = "Mirror Image"
    act_FilterHasLinked:        string = "Has Linked Image"
    act_HideEditorBefore:       string = "Hide Editor Before Capture"
    act_HideOutsideBox:         string = "Hide Outside Box"
    act_Highlight:              string = "Highlight"
    act_InvertOrder:            string = "Invert Order"
    act_InvertSelection:        string = "Invert Selection"
    act_Library:                string = "Library"
    act_Line:                   string = "Line"
    act_LocateCaptureFile:      string = "Locate Capture File"
    act_LocateLinkedImage:      string = "Locate Linked Image"
    act_MediumView:             string = "Medium View"
    act_Minimize:               string = "Minimize"
    act_MoveBackward:           string = "Move Backward"
    act_MoveForward:            string = "Move Forward"
    act_NewFromClipboard:       string = "New from Clipboard"
    act_NoImageInClipboard:     string = "No image in the clipboard"
    act_NothingToPaste:         string = "Nothing to paste"
    act_NewImage:               string = "New Image"
    act_OldestFirst:            string = "Oldest First"
    act_OpenImage:              string = "Open Image…"
    act_Options:                string = "Options…"
    act_PasteInsideImage:       string = "Paste Inside Image"
    act_Paste:                  string = "Paste"
    act_PixSel:                 string = "PixSel"
    act_Polygon:                string = "Polygon"
    act_Quit:                   string = "Quit"
    act_RecycleBin:             string = "Recycle Bin"
    act_Redo:                   string = "Redo"
    act_Rename:                 string = "Rename…"
    act_ResetRotation:          string = "Reset Rotation"
    act_RestoreDefaultStyles:   string = "Restore Default Styles"
    act_RestoreOriginal:        string = "Restore to Original"
    act_Restore:                string = "Restore"
    act_SaveAsImage:            string = "Save as Image…"
    act_SaveAsLinkedImage:      string = "Save as Linked Image…"
    act_SelectAll:              string = "Select All Objects"
    act_SelectSimilar:          string = "Select Similar Objects"
    act_Select:                 string = "Select"
    act_SendToClipboard:        string = "Send Capture to Clipboard"
    act_SendToEditor:           string = "Send Capture to Editor"
    act_SendToBack:             string = "Send to Back"
    act_ResizeImage:            string = "Resize Image…"
    act_RotateImageLeft:        string = "Rotate Image Left"
    act_RotateImageRight:       string = "Rotate Image Right"
    act_SendToFront:            string = "Send to Front"
    act_Shape:                  string = "Shape"
    act_SmartFill:              string = "Smart Fill"
    act_SmartMove:              string = "Smart Move"
    act_ShowEditor:             string = "Show Editor"
    act_Similarity:             string = "Similarity"
    act_SmallView:              string = "Small View"
    act_SmallerFirst:           string = "Smaller First"
    act_SnapToForms:            string = "Snap to Forms"
    act_Step:                   string = "Step"
    act_Text:                   string = "Text"
    act_TrimCapture:            string = "Trim Capture"
    act_UnsavedLinked:          string = "Unsaved Linked Image"
    act_Undo:                   string = "Undo"
    act_Ungroup:                string = "Ungroup"
    act_UnlinkImage:            string = "Unlink Image"
    act_UpToDateLinked:         string = "Up to Date Linked Image"
    act_UpdateLinkedImage:      string = "Update Linked Image"
    act_ZoomIn:                 string = "Zoom In"
    act_ZoomOut:                string = "Zoom Out"
    act_AlignLeft:              string = "Left"
    act_AlignCenter:            string = "Center"
    act_AlignRight:             string = "Right"
    act_AlignTop:               string = "Top"
    act_AlignMiddle:            string = "Middle"
    act_AlignBottom:            string = "Bottom"
    tip_LibraryFolders:         string = "Browse a folder or choose where Swag Capture stores captures"
    tip_SmallRecent:            string = "Small Recent View"
    tip_MediumRecent:           string = "Medium Recent View"
    tip_BigRecent:              string = "Big Recent View"
    tip_ToolShape:              string = "Add circles and rectangle to the capture"
    tip_ToolArrow:              string = "Add arrows to the capture"
    tip_ToolLine:               string = "Add lines to the capture"
    tip_ToolPolygon:            string = "Add polygons to the capture"
    tip_ToolText:               string = "Add some text to the capture"
    tip_ToolDraw:               string = "Add some free hand paint to the capture"
    tip_ToolHighlight:          string = "Highlight some parts of the capture"
    tip_ToolStep:               string = "Add some steps"
    tip_ToolImage:              string = "Add some images/effects"
    tip_ToolPixSel:             string = "Pixel Selection"
    tip_ToolCallout:            string = "Add speech-bubble callouts to the capture"
    tip_ToolFavorites:          string = "Save multiple quick styles in one single location"
    tip_ToolSelect:             string = "Select forms"
    tip_ResetSteps:             string = "Reset the global step count to 1"
    tip_InpSave:                string = "Save Capture as Image File"
    tip_InpCopy:                string = "Copy Image to Clipboard"
    tip_InpEdit:                string = "Open in Swag Capture Editor"
    tip_InpClose:               string = "Cancel and Discard Capture"
    tip_InpDraw:                string = "Free Draw Tool"
    tip_InpLine:                string = "Draw Straight Line"
    tip_InpCircle:              string = "Draw Circle or Ellipse"
    tip_InpRect:                string = "Draw Rectangle or Square"
    tip_InpArrow:               string = "Draw Arrow"
    tip_InpText:                string = "Add Text Annotation"
    tip_InpMarker:              string = "Highlight with Marker"

    // Wording of the rows the property grid generates from reflection. A property attribute
    // carries a compile-time literal, so the declared English below *is* the key
    // [[resolvePropertyText]] matches: adding a labeled row means adding a `prop_` field
    // whose declared value repeats the attribute string exactly.
    prop_EndSize:   string = "End Size"       // Label of the end-cap size of a line.
    prop_Font:      string = "Font"           // Label of the font family.
    prop_Joins:     string = "Joins"          // Label of the stroke join style.
    prop_Kind:      string = "Kind"           // Label of the image-form kind.
    prop_Line:      string = "Line"           // Label of the straight-or-curved choice.
    prop_Opacity:   string = "Opacity"        // Label of the opacity slider.
    prop_Outline:   string = "Outline"        // Label of the outer contour slider.
    prop_Place:     string = "Place"          // Label of the image placement.
    prop_Rotate:    string = "Rotate"         // Label of the rotation slider.
    prop_Round:     string = "Round"          // Corner-rounding slider, and the join style using a circular arc.
    prop_Scale:     string = "Scale"          // Label of the scale slider.
    prop_Shadow:    string = "Shadow"         // Label of the drop-shadow choice.
    prop_Size:      string = "Size"           // Label of the font size.
    prop_StartSize: string = "Start Size"     // Label of the start-cap size of a line.
    prop_Step:      string = "Step"           // Label of the step-numbering choice.
    prop_Strength:  string = "Strength"       // Label of the effect strength.
    prop_Style:     string = "Style"          // Label of the font style: regular, bold, italic or both.
    prop_Text:      string = "Text"           // Label of the edited text.
    prop_Thickness: string = "Thickness"      // Label of the stroke thickness.
    prop_Vertical:  string = "Vertical"       // Label of how the lines of a text stand down its box.

    prop_Straight: string = "Straight"      // Line entry: a segment.
    prop_Bezier:   string = "Bezier"        // Line entry: a curve.
    prop_NoShadow: string = "No Shadow"     // Shadow entry: none.
    prop_Small:    string = "Small"         // Shadow entry: a small one.

    prop_JoinNone:       string = "None"           // Join style with no explicit corner geometry.
    prop_JoinBevel:      string = "Bevel"          // Join style cutting the outer corner.
    prop_JoinMiter:      string = "Miter"          // Join style extending both edges.
    prop_JoinMiterBevel: string = "MiterBevel"     // Join style mitering when it can, beveling otherwise.

    prop_StyleRegular:    string = "Regular"        // Upright font style with normal weight.
    prop_StyleBold:       string = "Bold"           // Upright font style with bold weight.
    prop_StyleItalic:     string = "Italic"         // Slanted font style with normal weight.
    prop_StyleBoldItalic: string = "BoldItalic"     // Slanted font style with bold weight.

    prop_AlignLeftTop:     string = "LeftTop"         // Text alignment against the left or top edge.
    prop_AlignRightBottom: string = "RightBottom"     // Text alignment against the right or bottom edge.
    prop_Center:           string = "Center"          // Alignment or placement on the center, for text and for an image alike.

    prop_KindImage:    string = "Image"        // Image form showing a picture.
    prop_KindBlur:     string = "Blur"         // Image form blurring what it covers.
    prop_KindPixelate: string = "Pixelate"     // Image form pixelating what it covers.
    prop_KindZoom:     string = "Zoom"         // Image form magnifying what it covers.
    prop_KindCapture:  string = "Capture"      // Image form showing another capture.

    prop_PlaceFrame: string = "Frame"     // Image placement filling the frame.
    prop_PlaceFree:  string = "Free"      // Image placement left to the reader.

    prop_DrawCross:             string = "Draw Cross"                                                         // Label of [[CaptureOptions.drawCross]].
    prop_DrawCrossDesc:         string = "Show a large cross at the mouse position during capture"            // Description of [[CaptureOptions.drawCross]].
    prop_CaptureCursor:         string = "Capture Cursor"                                                     // Label of [[CaptureOptions.captureCursor]].
    prop_CaptureCursorDesc:     string = "Include the mouse cursor in the captured image"                     // Description of [[CaptureOptions.captureCursor]].
    prop_HideEditorBefore:      string = "Hide Editor Before"                                                 // Label of [[CaptureOptions.hideEditorBefore]].
    prop_HideEditorBeforeDesc:  string = "Temporarily hide the editor before starting the capture"            // Description of [[CaptureOptions.hideEditorBefore]].
    prop_SendToEditor:          string = "Send To Editor"                                                     // Label of [[CaptureOptions.sendToEditor]].
    prop_SendToEditorDesc:      string = "Send the captured image to the editor"                              // Description of [[CaptureOptions.sendToEditor]].
    prop_SendToClipboard:       string = "Send To Clipboard"                                                  // Label of [[CaptureOptions.sendToClipboard]].
    prop_SendToClipboardDesc:   string = "Copy the captured image to the clipboard"                           // Description of [[CaptureOptions.sendToClipboard]].
    prop_InPlaceEdit:           string = "In Place Edit"                                                      // Label of [[CaptureOptions.inPlaceEdit]].
    prop_InPlaceEditDesc:       string = "Edit captured area in place"                                        // Description of [[CaptureOptions.inPlaceEdit]].
    prop_Delay:                 string = "Delay"                                                              // Label of [[CaptureOptions.delay]].
    prop_DelayDesc:             string = "Set the delay time, in seconds, before capturing"                   // Description of [[CaptureOptions.delay]].
    prop_ClipToSelection:       string = "Clip To Selection"                                                  // Label of [[EditorOptions.clipToSelection]].
    prop_ClipToSelectionDesc:   string = "Mask everything outside the selected capture area"                  // Description of [[EditorOptions.clipToSelection]].
    prop_ConfirmLinked:         string = "Confirm Linked Overwrite"                                           // Label of [[EditorOptions.confirmLinkedOverwrite]].
    prop_ConfirmLinkedDesc:     string = "Require confirmation before overwriting a capture-linked image"     // Description of [[EditorOptions.confirmLinkedOverwrite]].
    prop_HideOnClose:           string = "Hide On Close"                                                      // Label of [[EditorOptions.hideOnClose]].
    prop_HideOnCloseDesc:       string = "Minimize the editor instead of closing it"                          // Description of [[EditorOptions.hideOnClose]].
    prop_EditBackColor:         string = "Edit Back Color"                                                    // Label of [[EditorOptions.editBackColor]].
    prop_EditBackColorDesc:     string = "Specify the background color of the capture editing window"         // Description of [[EditorOptions.editBackColor]].
}

private const FrenchStringsName = "lang/fr/capture.tweak"
private const FrenchStrings     = #include("../datas/lang/fr/capture.tweak")

private var g_AppStrings: AppStrings

// The reference English of every key, held apart from the live table.
//
// A language switch retargets [[appStrings]], and matching an attribute literal has to keep
// comparing against the wording the attributes declare. This table is never registered, so
// it keeps the values the struct declares for the whole run.
private var g_PropertyKeys: AppStrings

// Prefix of the fields that carry the wording of a generated property row.
private const PropertyKeyPrefix = "prop_"

// Returns the visible strings of Swag Capture in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Returns the active wording of a string declared by a property attribute.
//
// The grid builds its rows from compile-time attribute literals, so the literal is the key:
// the `prop_` field whose reference English repeats it answers with its wording in the
// active language. Answers `null` for a string no field claims, which is what leaves a
// symbol such as `"%"` or `"1...2...3..."` alone.
func resolvePropertyText(key: string)->string?
{
    let type      = assume cast(const *Swag.TypeInfoStruct, #typeof(AppStrings))
    let reference = cast(const [*] u8, &g_PropertyKeys)
    let active    = cast(const [*] u8, &g_AppStrings)

    for field in unwrap type.fields where Utf8.startsWith(field.name orelse "", PropertyKeyPrefix)
    {
        if cast(const *string, reference + field.offset)[] == key do
            return cast(const *string, active + field.offset)[]
    }

    return null
}

// Registers the Swag Capture string table, its embedded translations, and its property resolver.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "capture")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.Properties.setTextResolver(&resolvePropertyText)
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect Gui.validateStrings'AppStrings(cast(string, FrenchStrings))
    checkPropertyKeysAreDistinct()
}

// Fails the build when two `prop_` fields declare the same reference English.
//
// [[resolvePropertyText]] matches on that English and answers with the first field that
// carries it, so a repeated one would silently give every site the wording of whichever
// field came first — the kind of defect that only shows up in the language nobody on the
// team reads. Two sites that genuinely say the same English word share one field instead.
private func checkPropertyKeysAreDistinct()
{
    var keys: AppStrings
    let type = assume cast(const *Swag.TypeInfoStruct, #typeof(AppStrings))
    let data = cast(const [*] u8, &keys)

    for field in unwrap type.fields
    {
        let name = field.name orelse ""
        if not Utf8.startsWith(name, PropertyKeyPrefix) do
            continue

        let value = cast(const *string, data + field.offset)[]
        for other in type.fields
        {
            if other.offset >= field.offset do
                break
            if not Utf8.startsWith(other.name orelse "", PropertyKeyPrefix) do
                continue
            if cast(const *string, data + other.offset)[] != value do
                continue

            let clash = Format.toString("property key [[%]] is declared by both [[%]] and [[%]]", value, other.name orelse "", name)
            Swag.assert(false, clash)
        }
    }
}
