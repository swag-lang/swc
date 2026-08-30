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
    ui_MenuHelp:                string = "Help"
    ui_MenuAlign:               string = "Align"
    ui_MenuArrange:             string = "Arrange"
    ui_AllCaptures:             string = "All Items"
    ui_ImageBadge:              string = "IMAGE"
    ui_CommaSeparatedTags:      string = "Tags separated by commas"
    ui_Search:                  string = "Search"
    ui_BarView:                 string = "View"
    ui_Overlays:                string = "Overlays"
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
    msg_ResetStyles:            string = "This will reset the styles to the default values."     // Confirmation before restoring the default quick styles.
    dlg_TitleRenameCapture:     string = "Rename Capture"                                        // Title of the capture rename dialog.
    dlg_TitleEnterText:         string = "Enter Text"                                            // Title of the text-entry dialog.
    ui_Outline:                 string = "Outline"                                               // Label of the outline thickness slider.
    ui_PropFill:                string = "Fill"                                                  // Fill color swatch of the tool panel.
    ui_PropOutline:             string = "Outline"                                               // Outline color swatch of the tool panel.
    ui_PropColor:               string = "Color"                                                 // Stroke color swatch, for the forms that have no fill.
    ui_PropStart:               string = "Start"                                                 // Start cap of a line or an arrow.
    ui_PropEnd:                 string = "End"                                                   // End cap of a line or an arrow.
    ui_PropDash:                string = "Dash"                                                  // Dash pattern of a stroke.
    ui_PropPosition:            string = "Position"                                              // Category of the position and size rows.
    ui_PropSize:                string = "Size"                                                  // Size row of the position category.
    ui_ResetSteps:              string = "Reset"                                                 // Restarts the numbered-step counter.
    act_CaptureMonitor:         string = "Capture monitor %"                                     // Capture one monitor, by index.
    act_CaptureMonitorSize:     string = "Capture monitor % (%x%)"                               // Capture one monitor, with its size.
    act_ActualSize:             string = "Actual size"
    act_Arrow:                  string = "Arrow"
    act_BigView:                string = "Big view"
    act_Callout:                string = "Callout"
    act_CaptureActiveWindow:    string = "Capture active window"
    act_CaptureArea:            string = "Capture area"
    act_CaptureFullScreen:      string = "Capture full screen"
    act_CaptureLastArea:        string = "Capture last area"
    act_CaptureCursor:          string = "Capture mouse cursor"
    act_Clear:                  string = "Clear"
    act_ClearInsideImage:       string = "Clear inside image"
    act_CopyImageToClipboard:   string = "Copy image to clipboard"
    act_Copy:                   string = "Copy"
    act_Cut:                    string = "Cut"
    act_Delay1:                 string = "Delay before capture (1 second)"
    act_Delay2:                 string = "Delay before capture (2 seconds)"
    act_Delay5:                 string = "Delay before capture (5 seconds)"
    act_Delay9:                 string = "Delay before capture (9 seconds)"
    act_DelayBefore:            string = "Delay before capture"
    act_OneSecond:              string = "1 second"
    act_TwoSeconds:             string = "2 seconds"
    act_FiveSeconds:            string = "5 seconds"
    act_NineSeconds:            string = "9 seconds"
    act_NoDelay:                string = "No delay"
    act_DeletePermanently:      string = "Delete permanently"
    act_Delete:                 string = "Delete"
    act_DeselectAll:            string = "Deselect all objects"
    act_FilterNoLinked:         string = "Doesn't have linked image"
    act_ExpandCapture:          string = "Expand capture..."
    act_ExpandImage:            string = "Expand image..."
    act_Draw:                   string = "Draw"
    act_Duplicate:              string = "Duplicate"
    act_EditInPlace:            string = "Edit captured area in place"
    act_EmptyRecycleBin:        string = "Empty recycle bin"
    act_Favorites:              string = "Favorites"
    act_Fill:                   string = "Fill"
    act_FileDetails:            string = "File details"
    act_OpenSelected:           string = "Open"
    act_LocateImage:            string = "Show image in folder"
    act_EditTags:               string = "Edit tags..."
    act_ExportSelected:         string = "Export selected..."
    act_FavoriteCapture:        string = "Favorite"
    act_Rating:                 string = "Rating"
    act_NoRating:               string = "No rating"
    act_Rating1:                string = "1 star"
    act_Rating2:                string = "2 stars"
    act_Rating3:                string = "3 stars"
    act_Rating4:                string = "4 stars"
    act_Rating5:                string = "5 stars"
    act_ShowRatings:            string = "Ratings"
    act_ShowLinkMarkers:        string = "Link markers"
    act_BrowseFolder:           string = "Browse folder..."
    act_OpenLibraryFolder:      string = "Open library folder"
    act_ChooseLibraryFolder:    string = "Use another library folder..."
    act_UseDefaultLibrary:      string = "Use default library folder"
    act_Application:            string = "Application"
    act_AllApplications:        string = "All applications"
    act_Tags:                   string = "Tags"
    act_AllTags:                string = "All tags"
    act_ResetFilters:           string = "Clear filters"
    act_FilterAllItems:         string = "All items"
    act_FilterCaptures:         string = "Captures"
    act_FilterScreenCaptures:   string = "Screen captures"
    act_FilterImportedCaptures: string = "Imported captures"
    act_FilterImages:           string = "External images"
    act_FilterFavorites:        string = "Favorites only"
    act_FilterAnyRating:        string = "Any rating"
    act_FilterRating1:          string = "At least 1 star"
    act_FilterRating2:          string = "At least 2 stars"
    act_FilterRating3:          string = "At least 3 stars"
    act_FilterRating4:          string = "At least 4 stars"
    act_FilterRating5:          string = "5 stars"
    act_SortCapturedAt:         string = "Capture time"
    act_SortModified:           string = "Modified time"
    act_SortName:               string = "Name"
    act_SortApplication:        string = "Application"
    act_SortWindowTitle:        string = "Window title"
    act_SortDimensions:         string = "Image dimensions"
    act_SmallerImagesFirst:     string = "Smaller images first"
    act_SortFileSize:           string = "File size"
    act_FitToView:              string = "Fit to view"
    act_Flatten:                string = "Flatten"
    act_FlattenAll:             string = "Flatten all"
    act_FlipImage:              string = "Flip image"
    act_FreezeSelection:        string = "Freeze selection"
    act_Group:                  string = "Group"
    act_MirrorImage:            string = "Mirror image"
    act_FilterHasLinked:        string = "Has linked image"
    act_HideEditorBefore:       string = "Hide editor before capture"
    act_HideOutsideBox:         string = "Hide outside box"
    act_Highlight:              string = "Highlight"
    act_InvertOrder:            string = "Invert order"
    act_InvertSelection:        string = "Invert selection"
    act_Library:                string = "Library"
    act_Line:                   string = "Line"
    act_LocateCaptureFile:      string = "Locate capture file"
    act_LocateLinkedImage:      string = "Locate linked image"
    act_MediumView:             string = "Medium view"
    act_Minimize:               string = "Minimize"
    act_MoveBackward:           string = "Move backward"
    act_MoveForward:            string = "Move forward"
    act_NewFromClipboard:       string = "New from clipboard"
    act_NewImage:               string = "New image"
    act_OldestFirst:            string = "Oldest first"
    act_OpenImage:              string = "Open image..."
    act_Options:                string = "Options..."
    act_PasteInsideImage:       string = "Paste inside image"
    act_Paste:                  string = "Paste"
    act_PixSel:                 string = "PixSel"
    act_Polygon:                string = "Polygon"
    act_Quit:                   string = "Quit"
    act_RecycleBin:             string = "Recycle bin"
    act_Redo:                   string = "Redo"
    act_Rename:                 string = "Rename..."
    act_ResetRotation:          string = "Reset rotation"
    act_RestoreDefaultStyles:   string = "Restore default styles"
    act_RestoreOriginal:        string = "Restore to original"
    act_Restore:                string = "Restore"
    act_SaveAsImage:            string = "Save as image..."
    act_SaveAsLinkedImage:      string = "Save as linked image..."
    act_SelectAll:              string = "Select all objects"
    act_SelectSimilar:          string = "Select similar objects"
    act_Select:                 string = "Select"
    act_SendToClipboard:        string = "Send capture to clipboard"
    act_SendToEditor:           string = "Send capture to editor"
    act_SendToBack:             string = "Send to back"
    act_ResizeImage:            string = "Resize image..."
    act_RotateImageLeft:        string = "Rotate image left"
    act_RotateImageRight:       string = "Rotate image right"
    act_SendToFront:            string = "Send to front"
    act_Shape:                  string = "Shape"
    act_SmartFill:              string = "Smart fill"
    act_SmartMove:              string = "Smart move"
    act_ShowEditor:             string = "Show editor"
    act_Similarity:             string = "Similarity"
    act_SmallView:              string = "Small view"
    act_SmallerFirst:           string = "Smaller first"
    act_SnapToForms:            string = "Snap to forms"
    act_Step:                   string = "Step"
    act_Text:                   string = "Text"
    act_TrimCapture:            string = "Trim capture"
    act_UnsavedLinked:          string = "Unsaved linked image"
    act_Undo:                   string = "Undo"
    act_Ungroup:                string = "Ungroup"
    act_UnlinkImage:            string = "Unlink image"
    act_UpToDateLinked:         string = "Up to date linked image"
    act_UpdateLinkedImage:      string = "Update linked image"
    act_ZoomIn:                 string = "Zoom in"
    act_ZoomOut:                string = "Zoom out"
    act_AlignLeft:              string = "Left"
    act_AlignCenter:            string = "Center"
    act_AlignRight:             string = "Right"
    act_AlignTop:               string = "Top"
    act_AlignMiddle:            string = "Middle"
    act_AlignBottom:            string = "Bottom"
    tip_LibraryFolders:         string = "Browse a folder or choose where Swag Capture stores captures"
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
    tip_InpEdit:                string = "Open in Swag Capture editor"
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
    // [[resolvePropertyText]] matches: adding a labeled row means adding a `prop_` field
    // whose declared value repeats the attribute string exactly.
    prop_EndSize:   string = "End Size"       // Label of the end-cap size of a line.
    prop_Font:      string = "Font"           // Label of the font family.
    prop_Joins:     string = "Joins"          // Label of the stroke join style.
    prop_Kind:      string = "Kind"           // Label of the image-form kind.
    prop_Line:      string = "Line"           // Label of the straight-or-curved choice.
    prop_Opacity:   string = "Opacity"        // Label of the opacity slider.
    prop_Place:     string = "Place"          // Label of the image placement.
    prop_Rotate:    string = "Rotate"         // Label of the rotation slider.
    prop_Round:     string = "Round"          // Corner-rounding slider, and the join style using a circular arc.
    prop_Scale:     string = "Scale"          // Label of the scale slider.
    prop_Shadow:    string = "Shadow"         // Label of the drop-shadow choice.
    prop_Size:      string = "Size"           // Label of the font size.
    prop_StartSize: string = "Start Size"     // Label of the start-cap size of a line.
    prop_Step:      string = "Step"           // Label of the step-numbering choice.
    prop_Strength:  string = "Strength"       // Label of the effect strength.
    prop_Text:      string = "Text"           // Label of the edited text.
    prop_Thickness: string = "Thickness"      // Label of the stroke thickness.

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
        if (reference + field.offset)[as string] != key do
            continue
        return (active + field.offset)[as string]
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

        let value = (data + field.offset)[as string]
        for g in type.fields!
        {
            let other = g!
            if other.offset >= field.offset do
                break
            if !Utf8.startsWith(other.name orelse "", PropertyKeyPrefix) do
                continue
            if (data + other.offset)[as string] != value do
                continue

            let clash = Format.toString("property key [[%]] is declared by both [[%]] and [[%]]", value, other.name orelse "", name)
            Debug.assert(false, clash.toString())
        }
    }
}
