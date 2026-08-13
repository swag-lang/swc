#global public

using Core, Gui

// Visible strings of sCapture.
//
// The declared values are the reference English wording, and each field is one
// translatable key. Translations live in `datas/lang/<tag>/scapture.tweak`; a key a
// language file omits keeps its reference value. Read the active table through
// [[appStrings]]; never keep a copy across a language switch.
struct AppStrings
{
    ui_MenuFile:                string = "File"
    ui_MenuCapture:             string = "Capture"
    ui_MenuEdit:                string = "Edit"
    ui_MenuImage:               string = "Image"
    ui_MenuView:                string = "View"
    ui_MenuHelp:                string = "Help"
    ui_MenuAlign:               string = "Align"
    ui_MenuArrange:             string = "Arrange"
    ui_AllCaptures:             string = "All Items"
    ui_ImageBadge:              string = "IMAGE"
    ui_CommaSeparatedTags:      string = "Tags separated by commas"
    ui_Search:                  string = "Search"
    ui_BarSize:                 string = "Size"
    ui_BarSort:                 string = "Sort"
    ui_BarFilter:               string = "Filter"
    ui_BarFolders:              string = "Folders"
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
    ui_Frozen:                  string = "Selection is frozen"
    ui_Desktop:                 string = "Desktop"
    ui_MyImages:                string = "My Images"
    ui_CommonImages:            string = "Images"
    dlg_TitleOptions:           string = "Options"
    dlg_TitleDetails:           string = "Details"
    dlg_TitleLoadImage:         string = "Load Image"
    dlg_TitleSaveAsImage:       string = "Save As Image"
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
    msg_FailedDuplicate:        string = "Failed to duplicate capture"
    msg_FailedLocateCapture:    string = "Failed to locate capture file"
    msg_FailedLocateLinked:     string = "Failed to locate linked image"
    msg_FailedLoadImage:        string = "Failed to load image"
    msg_FailedSaveFile:         string = "Failed to save file"
    msg_FailedSaveCapture:      string = "Failed to save capture file: %"
    msg_FailedRename:           string = "Failed to rename capture"
    msg_FailedCopyImage:        string = "Failed to copy image"
    msg_FailedLoadFile:         string = "Failed to load file: %"
    msg_FailedOpenLibrary:      string = "Cannot open the library folder"
    msg_FailedSaveMetadata:     string = "Cannot save capture metadata"
    msg_FailedExportCaptures:   string = "Cannot export the selected captures"
    msg_ShortcutTaken:          string = "Cannot register global shortcut '%'. "
    msg_ShortcutTakenWhy:       string = "Another running application is probably already using it!"
    msg_AboutBuild:             string = "Build of %{f}"
    msg_AboutSource:            string = "sCapture is open source and written in <url>Swag</url>. Its code is <url>here</url>."     // About box: what the product is made of.
    msg_AboutCopyright:         string = "Copyright © % Christophe Beaudet"                                                         // About box: the copyright line, given the year.
    msg_ResetStyles:            string = "This will reset the styles to the default values."                                        // Confirmation before restoring the default quick styles.
    dlg_TitleRenameCapture:     string = "Rename Capture"                                                                           // Title of the capture rename dialog.
    dlg_TitleEnterText:         string = "Enter Text"                                                                               // Title of the text-entry dialog.
    ui_Outline:                 string = "Outline"                                                                                  // Label of the outline thickness slider.
    ui_PropFill:                string = "Fill"                                                                                     // Fill color swatch of the tool panel.
    ui_PropOutline:             string = "Outline"                                                                                  // Outline color swatch of the tool panel.
    ui_PropColor:               string = "Color"                                                                                    // Stroke color swatch, for the forms that have no fill.
    ui_PropStart:               string = "Start"                                                                                    // Start cap of a line or an arrow.
    ui_PropEnd:                 string = "End"                                                                                      // End cap of a line or an arrow.
    ui_PropDash:                string = "Dash"                                                                                     // Dash pattern of a stroke.
    ui_PropPosition:            string = "Position"                                                                                 // Category of the position and size rows.
    ui_PropSize:                string = "Size"                                                                                     // Size row of the position category.
    ui_ResetSteps:              string = "Reset"                                                                                    // Restarts the numbered-step counter.
    act_CaptureMonitor:         string = "Capture Monitor %"                                                                        // Capture one monitor, by index.
    act_CaptureMonitorSize:     string = "Capture Monitor % (%x%)"                                                                  // Capture one monitor, with its size.
    act_About:                  string = "About..."
    act_ActualSize:             string = "Actual Size"
    act_Arrow:                  string = "Arrow"
    act_BigView:                string = "Big view"
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
    act_Delay1:                 string = "Delay Before Capture (1 second)"
    act_Delay2:                 string = "Delay Before Capture (2 seconds)"
    act_Delay5:                 string = "Delay Before Capture (5 seconds)"
    act_Delay9:                 string = "Delay Before Capture (9 seconds)"
    act_DelayBefore:            string = "Delay Before Capture"
    act_OneSecond:              string = "1 second"
    act_TwoSeconds:             string = "2 seconds"
    act_FiveSeconds:            string = "5 seconds"
    act_NineSeconds:            string = "9 seconds"
    act_NoDelay:                string = "No Delay"
    act_DeletePermanently:      string = "Delete Permanently"
    act_Delete:                 string = "Delete"
    act_DeselectAll:            string = "Deselect All Objects"
    act_FilterNoLinked:         string = "Doesn't Have Linked Image"
    act_ExpandCapture:          string = "Expand Capture..."
    act_ExpandImage:            string = "Expand Image..."
    act_Draw:                   string = "Draw"
    act_Duplicate:              string = "Duplicate"
    act_EditInPlace:            string = "Edit Captured Area In Place"
    act_EmptyRecycleBin:        string = "Empty Recycle Bin"
    act_Favorites:              string = "Favorites"
    act_Fill:                   string = "Fill"
    act_FileDetails:            string = "File Details"
    act_OpenSelected:           string = "Open"
    act_LocateImage:            string = "Show Image in Folder"
    act_EditTags:               string = "Edit Tags..."
    act_ExportSelected:         string = "Export Selected..."
    act_FavoriteCapture:        string = "Favorite"
    act_Rating:                 string = "Rating"
    act_NoRating:               string = "No Rating"
    act_Rating1:                string = "1 Star"
    act_Rating2:                string = "2 Stars"
    act_Rating3:                string = "3 Stars"
    act_Rating4:                string = "4 Stars"
    act_Rating5:                string = "5 Stars"
    act_BrowseFolder:           string = "Browse Folder..."
    act_OpenLibraryFolder:      string = "Open Library Folder"
    act_ChooseLibraryFolder:    string = "Use Another Library Folder..."
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
    act_FitToView:              string = "Fit To View"
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
    act_MediumView:             string = "Medium view"
    act_Minimize:               string = "Minimize"
    act_MoveBackward:           string = "Move Backward"
    act_MoveForward:            string = "Move Forward"
    act_NewFromClipboard:       string = "New From Clipboard"
    act_NewImage:               string = "New Image"
    act_OldestFirst:            string = "Oldest First"
    act_OpenImage:              string = "Open Image..."
    act_Options:                string = "Options..."
    act_PasteInsideImage:       string = "Paste Inside Image"
    act_Paste:                  string = "Paste"
    act_PixSel:                 string = "PixSel"
    act_Polygon:                string = "Polygon"
    act_Quit:                   string = "Quit"
    act_RecycleBin:             string = "Recycle Bin"
    act_Redo:                   string = "Redo"
    act_Rename:                 string = "Rename..."
    act_ResetRotation:          string = "Reset Rotation"
    act_RestoreDefaultStyles:   string = "Restore Default Styles"
    act_RestoreOriginal:        string = "Restore to Original"
    act_Restore:                string = "Restore"
    act_SaveAsImage:            string = "Save As Image..."
    act_SaveAsLinkedImage:      string = "Save As Linked Image..."
    act_SelectAll:              string = "Select All Objects"
    act_SelectSimilar:          string = "Select Similar Objects"
    act_Select:                 string = "Select"
    act_SendToClipboard:        string = "Send Capture To Clipboard"
    act_SendToEditor:           string = "Send Capture To Editor"
    act_SendToBack:             string = "Send To Back"
    act_ResizeImage:            string = "Resize Image..."
    act_RotateImageLeft:        string = "Rotate Image Left"
    act_RotateImageRight:       string = "Rotate Image Right"
    act_SendToFront:            string = "Send To Front"
    act_Shape:                  string = "Shape"
    act_SmartFill:              string = "Smart Fill"
    act_SmartMove:              string = "Smart Move"
    act_ShowEditor:             string = "Show Editor"
    act_Similarity:             string = "Similarity"
    act_SmallView:              string = "Small view"
    act_SmallerFirst:           string = "Smaller First"
    act_SnapToForms:            string = "Snap To Forms"
    act_Step:                   string = "Step"
    act_Text:                   string = "Text"
    act_TrimCapture:            string = "Trim Capture"
    act_UnsavedLinked:          string = "UnSaved Linked Image"
    act_Undo:                   string = "Undo"
    act_Ungroup:                string = "Ungroup"
    act_UnlinkImage:            string = "Unlink Image"
    act_UpToDateLinked:         string = "Up To Date Linked Image"
    act_UpdateLinkedImage:      string = "Update Linked Image"
    act_ZoomIn:                 string = "Zoom In"
    act_ZoomOut:                string = "Zoom Out"
    act_AlignLeft:              string = "Left"
    act_AlignCenter:            string = "Center"
    act_AlignRight:             string = "Right"
    act_AlignTop:               string = "Top"
    act_AlignMiddle:            string = "Middle"
    act_AlignBottom:            string = "Bottom"
    tip_LibraryFolders:         string = "Browse a folder or choose where sCapture stores captures"
    tip_SmallRecent:            string = "Small recent view"
    tip_MediumRecent:           string = "Medium recent view"
    tip_BigRecent:              string = "Big recent view"
    tip_ToolShape:              string = "Add circles and rectangle to the capture"
    tip_ToolArrow:              string = "Add arrows to the capture"
    tip_ToolLine:               string = "Add lines to the capture"
    tip_ToolPolygon:            string = "Add polygons to the capture"
    tip_ToolText:               string = "Add some text to the capture"
    tip_ToolDraw:               string = "Add some free hand paint to the capture"
    tip_ToolHighlight:          string = "Highlight some parts of the capture"
    tip_ToolStep:               string = "Add some steps"
    tip_ToolImage:              string = "Add some images/effects"
    tip_ToolPixSel:             string = "Pixel selection"
    tip_ToolCallout:            string = "Add speech-bubble callouts to the capture"
    tip_ToolFavorites:          string = "Save multiple quick styles in one single location"
    tip_ToolSelect:             string = "Select forms"
    tip_ResetSteps:             string = "Reset the global step count to 1"
    tip_InpSave:                string = "Save capture as image file"
    tip_InpCopy:                string = "Copy image to clipboard"
    tip_InpEdit:                string = "Open in sCapture editor"
    tip_InpClose:               string = "Cancel and discard capture"
    tip_InpDraw:                string = "Free draw tool"
    tip_InpLine:                string = "Draw straight line"
    tip_InpCircle:              string = "Draw circle or ellipse"
    tip_InpRect:                string = "Draw rectangle or square"
    tip_InpArrow:               string = "Draw arrow"
    tip_InpText:                string = "Add text annotation"
    tip_InpMarker:              string = "Highlight with marker"

    // Wording of the rows the property grid generates from reflection. A property attribute
    // carries a compile-time literal, so the declared English below *is* the key
    // [[resolvePropertyText]] matches: adding a row means adding a `prop_` field whose
    // declared value repeats the attribute string exactly.
    prop_Align:         string = "Align"              // Label of the horizontal text alignment.
    prop_AlignVertical: string = "Vertical Align"     // Label of the vertical text alignment.
    prop_EndSize:       string = "End Size"           // Label of the end-cap size of a line.
    prop_Effects:       string = "Effects"            // Category of the scale, rotation, opacity and shadow rows.
    prop_Font:          string = "Font"               // Label of the font family.
    prop_FontStyle:     string = "Font Style"         // Label of the font style.
    prop_Joins:         string = "Joins"              // Label of the stroke join style.
    prop_Kind:          string = "Kind"               // Label of the image-form kind.
    prop_Line:          string = "Line"               // Label of the straight-or-curved choice.
    prop_Opacity:       string = "Opacity"            // Label of the opacity slider.
    prop_Place:         string = "Place"              // Label of the image placement.
    prop_Rotate:        string = "Rotate"             // Label of the rotation slider.
    prop_Round:         string = "Round"              // Corner-rounding slider, and the join style using a circular arc.
    prop_Scale:         string = "Scale"              // Label of the scale slider.
    prop_Shadow:        string = "Shadow"             // Label of the drop-shadow choice.
    prop_Size:          string = "Size"               // Label of the font size.
    prop_StartSize:     string = "Start Size"         // Label of the start-cap size of a line.
    prop_Step:          string = "Step"               // Label of the step-numbering choice.
    prop_Strength:      string = "Strength"           // Label of the effect strength.
    prop_Text:          string = "Text"               // Label of the edited text.
    prop_Thickness:     string = "Thickness"          // Label of the stroke thickness.

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
    prop_ShowToolBarLabels:     string = "Show Tool Bar Labels"                                               // Label of [[EditorOptions.showToolBarLabels]].
    prop_ShowToolBarLabelsDesc: string = "Show text labels in the main toolbar"                               // Description of [[EditorOptions.showToolBarLabels]].
    prop_ClipToSelection:       string = "Clip To Selection"                                                  // Label of [[EditorOptions.clipToSelection]].
    prop_ClipToSelectionDesc:   string = "Mask everything outside the selected capture area"                  // Description of [[EditorOptions.clipToSelection]].
    prop_ConfirmLinked:         string = "Confirm Linked Overwrite"                                           // Label of [[EditorOptions.confirmLinkedOverwrite]].
    prop_ConfirmLinkedDesc:     string = "Require confirmation before overwriting a capture-linked image"     // Description of [[EditorOptions.confirmLinkedOverwrite]].
    prop_HideOnClose:           string = "Hide On Close"                                                      // Label of [[EditorOptions.hideOnClose]].
    prop_HideOnCloseDesc:       string = "Minimize the editor instead of closing it"                          // Description of [[EditorOptions.hideOnClose]].
    prop_Theme:                 string = "Theme"                                                              // Label of [[EditorOptions.theme]].
    prop_ThemeDesc:             string = "sCapture theme"                                                     // Description of [[EditorOptions.theme]].
    prop_Language:              string = "Language"                                                           // Label of [[EditorOptions.language]].
    prop_LanguageDesc:          string = "Language of the user interface"                                     // Description of [[EditorOptions.language]].
    prop_EditBackColor:         string = "Edit Back Color"                                                    // Label of [[EditorOptions.editBackColor]].
    prop_EditBackColorDesc:     string = "Specify the background color of the capture editing window"         // Description of [[EditorOptions.editBackColor]].

    prop_ThemeDark:  string = "Dark"      // Theme entry: the dark one.
    prop_ThemeLight: string = "Light"     // Theme entry: the light one.

    prop_LanguageSystem:  string = "System"      // Language entry: follow the Windows language.
    prop_LanguageEnglish: string = "English"     // Language entry: the reference wording.
    prop_LanguageFrench:  string = "French"      // Language entry: French.
}

private const FrenchStringsName = "lang/fr/scapture.tweak"
private const FrenchStrings = #include("../datas/lang/fr/scapture.tweak")

private var g_AppStrings: AppStrings

// The reference English of every key, held apart from the live table.
//
// A language switch retargets [[appStrings]], and matching an attribute literal has to keep
// comparing against the wording the attributes declare. This table is never registered, so
// it keeps the values the struct declares for the whole run.
private var g_PropertyKeys: AppStrings

// Prefix of the fields that carry the wording of a generated property row.
private const PropertyKeyPrefix = "prop_"

// Returns the visible strings of sCapture in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Returns the active wording of a string declared by a property attribute.
//
// The grid builds its rows from compile-time attribute literals, so the literal is the key:
// the `prop_` field whose reference English repeats it answers with its wording in the
// active language. Answers `null` for a string no field claims, which is what leaves a
// symbol such as `"%"` or `"1...2...3..."` alone.
func resolvePropertyText(key: string)->#null string
{
    let type      = cast(const *Swag.TypeInfoStruct) #typeof(AppStrings)
    let reference = cast(const [*] u8) &g_PropertyKeys
    let active    = cast(const [*] u8) &g_AppStrings

    for f in type.fields!
    {
        let field = f!
        if !Utf8.startsWith(field.name orelse "", PropertyKeyPrefix) do
            continue
        if dref cast(const *string) (reference + field.offset) != key do
            continue
        return dref cast(const *string) (active + field.offset)
    }

    return null
}

// Registers the sCapture string table, its embedded translations, and its property resolver.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "scapture")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.Properties.setTextResolver(&resolvePropertyText)
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
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
    let type = cast(const *Swag.TypeInfoStruct) #typeof(AppStrings)
    let data = cast(const [*] u8) &keys

    for f in type.fields!
    {
        let field = f!
        let name  = field.name orelse ""
        if !Utf8.startsWith(name, PropertyKeyPrefix) do
            continue

        let value = dref cast(const *string) (data + field.offset)
        for g in type.fields!
        {
            let other = g!
            if other.offset >= field.offset do
                break
            if !Utf8.startsWith(other.name orelse "", PropertyKeyPrefix) do
                continue
            if dref cast(const *string) (data + other.offset) != value do
                continue

            let clash = Format.toString("property key [[%]] is declared by both [[%]] and [[%]]", value, other.name orelse "", name)
            Debug.assert(false, clash.toString())
        }
    }
}
