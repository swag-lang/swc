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
    ui_MenuFile:              string = "File"
    ui_MenuCapture:           string = "Capture"
    ui_MenuEdit:              string = "Edit"
    ui_MenuImage:             string = "Image"
    ui_MenuView:              string = "View"
    ui_MenuHelp:              string = "Help"
    ui_MenuAlign:             string = "Align"
    ui_MenuArrange:           string = "Arrange"
    ui_AllCaptures:           string = "All Captures"
    ui_Search:                string = "Search"
    ui_BarSize:               string = "Size"
    ui_BarSort:               string = "Sort"
    ui_BarFilter:             string = "Filter"
    ui_BarTrash:              string = "Trash"
    ui_RemoveQuickStyle:      string = "Remove Quick Style"
    ui_SectionEditor:         string = "Editor"
    ui_SectionApplication:    string = "Application"
    ui_DetailFile:            string = "<b>File</b>"
    ui_DetailLinkedImage:     string = "<b>Linked Image</b>"
    ui_DetailImageSize:       string = "<b>Image Size</b>"
    ui_Width:                 string = "Width"
    ui_Height:                string = "Height"
    ui_KeepRatio:             string = "Keep Ratio"
    ui_Frozen:                string = "Selection is frozen"
    ui_Desktop:               string = "Desktop"
    ui_MyImages:              string = "My Images"
    ui_CommonImages:          string = "Images"
    dlg_TitleOptions:         string = "Options"
    dlg_TitleDetails:         string = "Details"
    dlg_TitleLoadImage:       string = "Load Image"
    dlg_TitleSaveAsImage:     string = "Save As Image"
    dlg_TitleResizeImage:     string = "Resize Image"
    dlg_TitleExpandImage:     string = "Expand Image"
    dlg_TitleExpandCapture:   string = "Expand Capture"
    dlg_BtnCreate:            string = "Create"
    dlg_BtnResize:            string = "Resize"
    dlg_BtnLoad:              string = "Load"
    dlg_BtnSave:              string = "Save"
    msg_RemoveAssociation:    string = "This will remove the image association."
    msg_DeleteCaptures:       string = "This will delete the capture file(s)."
    msg_EraseTrash:           string = "This will permanently erase every capture in the recycle bin."
    msg_EraseSelected:        string = "This will permanently erase the selected capture(s)."
    msg_FailedDuplicate:      string = "Failed to duplicate capture"
    msg_FailedLocateCapture:  string = "Failed to locate capture file"
    msg_FailedLocateLinked:   string = "Failed to locate linked image"
    msg_FailedLoadImage:      string = "Failed to load image"
    msg_FailedSaveFile:       string = "Failed to save file"
    msg_FailedSaveCapture:    string = "Failed to save capture file: %"
    msg_FailedRename:         string = "Failed to rename capture"
    msg_FailedCopyImage:      string = "Failed to copy image"
    msg_FailedLoadFile:       string = "Failed to load file: %"
    msg_ShortcutTaken:        string = "Cannot register global shortcut '%'. "
    msg_ShortcutTakenWhy:     string = "Another running application is probably already using it!"
    msg_AboutBuild:           string = "Build on %{j}"
    msg_ResetStyles:          string = "This will reset the styles to the default values."     // Confirmation before restoring the default quick styles.
    dlg_TitleRenameCapture:   string = "Rename Capture"                                        // Title of the capture rename dialog.
    dlg_TitleEnterText:       string = "Enter Text"                                            // Title of the text-entry dialog.
    ui_Outline:               string = "Outline"                                               // Label of the outline thickness slider.
    ui_PropFill:              string = "Fill"                                                  // Fill color swatch of the tool panel.
    ui_PropOutline:           string = "Outline"                                               // Outline color swatch of the tool panel.
    ui_PropColor:             string = "Color"                                                 // Stroke color swatch, for the forms that have no fill.
    ui_PropStart:             string = "Start"                                                 // Start cap of a line or an arrow.
    ui_PropEnd:               string = "End"                                                   // End cap of a line or an arrow.
    ui_PropDash:              string = "Dash"                                                  // Dash pattern of a stroke.
    ui_PropPosition:          string = "Position"                                              // Category of the position and size rows.
    ui_PropSize:              string = "Size"                                                  // Size row of the position category.
    ui_ResetSteps:            string = "Reset"                                                 // Restarts the numbered-step counter.
    act_CaptureMonitor:       string = "Capture Monitor %"                                     // Capture one monitor, by index.
    act_CaptureMonitorSize:   string = "Capture Monitor % (%x%)"                               // Capture one monitor, with its size.
    act_About:                string = "About..."
    act_ActualSize:           string = "Actual Size"
    act_Arrow:                string = "Arrow"
    act_BigView:              string = "Big view"
    act_Callout:              string = "Callout"
    act_CaptureActiveWindow:  string = "Capture Active Window"
    act_CaptureArea:          string = "Capture Area"
    act_CaptureFullScreen:    string = "Capture Full Screen"
    act_CaptureLastArea:      string = "Capture Last Area"
    act_CaptureCursor:        string = "Capture Mouse Cursor"
    act_ClearInsideImage:     string = "Clear Inside Image"
    act_CopyImageToClipboard: string = "Copy Image to Clipboard"
    act_Copy:                 string = "Copy"
    act_Cut:                  string = "Cut"
    act_Delay1:               string = "Delay Before Capture (1 second)"
    act_Delay2:               string = "Delay Before Capture (2 seconds)"
    act_Delay5:               string = "Delay Before Capture (5 seconds)"
    act_Delay9:               string = "Delay Before Capture (9 seconds)"
    act_DelayBefore:          string = "Delay Before Capture"
    act_OneSecond:            string = "1 second"
    act_TwoSeconds:           string = "2 seconds"
    act_FiveSeconds:          string = "5 seconds"
    act_NineSeconds:          string = "9 seconds"
    act_NoDelay:              string = "No Delay"
    act_DeletePermanently:    string = "Delete Permanently"
    act_Delete:               string = "Delete"
    act_DeselectAll:          string = "Deselect All Objects"
    act_FilterNoLinked:       string = "Doesn't Have Linked Image"
    act_Draw:                 string = "Draw"
    act_Duplicate:            string = "Duplicate"
    act_EditInPlace:          string = "Edit Captured Area In Place"
    act_EmptyRecycleBin:      string = "Empty Recycle Bin"
    act_Favorites:            string = "Favorites"
    act_FileDetails:          string = "File Details"
    act_SortFileSize:         string = "File Size"
    act_FitToView:            string = "Fit To View"
    act_FreezeSelection:      string = "Freeze Selection"
    act_Group:                string = "Group"
    act_FilterHasLinked:      string = "Has Linked Image"
    act_HideEditorBefore:     string = "Hide Editor Before Capture"
    act_HideOutsideBox:       string = "Hide Outside Box"
    act_Highlight:            string = "Highlight"
    act_InvertOrder:          string = "Invert Order"
    act_InvertSelection:      string = "Invert Selection"
    act_Library:              string = "Library"
    act_Line:                 string = "Line"
    act_LocateCaptureFile:    string = "Locate Capture File"
    act_LocateLinkedImage:    string = "Locate Linked Image"
    act_MediumView:           string = "Medium view"
    act_Minimize:             string = "Minimize"
    act_MoveBackward:         string = "Move Backward"
    act_MoveForward:          string = "Move Forward"
    act_NewFromClipboard:     string = "New From Clipboard"
    act_NewImage:             string = "New Image"
    act_OldestFirst:          string = "Oldest First"
    act_OpenImage:            string = "Open Image..."
    act_Options:              string = "Options..."
    act_PasteInsideImage:     string = "Paste Inside Image"
    act_Paste:                string = "Paste"
    act_PixSel:               string = "PixSel"
    act_Polygon:              string = "Polygon"
    act_Quit:                 string = "Quit"
    act_RecycleBin:           string = "Recycle Bin"
    act_Redo:                 string = "Redo"
    act_Rename:               string = "Rename..."
    act_ResetRotation:        string = "Reset Rotation"
    act_RestoreDefaultStyles: string = "Restore Default Styles"
    act_RestoreOriginal:      string = "Restore to Original"
    act_Restore:              string = "Restore"
    act_SaveAsImage:          string = "Save As Image..."
    act_SaveAsLinkedImage:    string = "Save As Linked Image..."
    act_SelectAll:            string = "Select All Objects"
    act_SelectSimilar:        string = "Select Similar Objects"
    act_Select:               string = "Select"
    act_SendToClipboard:      string = "Send Capture To Clipboard"
    act_SendToEditor:         string = "Send Capture To Editor"
    act_SendToBack:           string = "Send To Back"
    act_SendToFront:          string = "Send To Front"
    act_Shape:                string = "Shape"
    act_ShowEditor:           string = "Show Editor"
    act_Similarity:           string = "Similarity"
    act_SmallView:            string = "Small view"
    act_SmallerFirst:         string = "Smaller First"
    act_SnapToForms:          string = "Snap To Forms"
    act_Step:                 string = "Step"
    act_Text:                 string = "Text"
    act_UnsavedLinked:        string = "UnSaved Linked Image"
    act_Undo:                 string = "Undo"
    act_Ungroup:              string = "Ungroup"
    act_UnlinkImage:          string = "Unlink Image"
    act_UpToDateLinked:       string = "Up To Date Linked Image"
    act_UpdateLinkedImage:    string = "Update Linked Image"
    act_SortWriteTime:        string = "Write Time"
    act_ZoomIn:               string = "Zoom In"
    act_ZoomOut:              string = "Zoom Out"
    act_AlignLeft:            string = "Left"
    act_AlignCenter:          string = "Center"
    act_AlignRight:           string = "Right"
    act_AlignTop:             string = "Top"
    act_AlignMiddle:          string = "Middle"
    act_AlignBottom:          string = "Bottom"
    tip_ShowLibrary:          string = "Display captures library"
    tip_SmallRecent:          string = "Small recent view"
    tip_MediumRecent:         string = "Medium recent view"
    tip_BigRecent:            string = "Big recent view"
    tip_ToolShape:            string = "Add circles and rectangle to the capture"
    tip_ToolArrow:            string = "Add arrows to the capture"
    tip_ToolLine:             string = "Add lines to the capture"
    tip_ToolPolygon:          string = "Add polygons to the capture"
    tip_ToolText:             string = "Add some text to the capture"
    tip_ToolDraw:             string = "Add some free hand paint to the capture"
    tip_ToolHighlight:        string = "Highlight some parts of the capture"
    tip_ToolStep:             string = "Add some steps"
    tip_ToolImage:            string = "Add some images/effects"
    tip_ToolPixSel:           string = "Pixel selection"
    tip_ToolCallout:          string = "Add speech-bubble callouts to the capture"
    tip_ToolFavorites:        string = "Save multiple quick styles in one single location"
    tip_ToolSelect:           string = "Select forms"
    tip_ResetSteps:           string = "Reset the global step count to 1"
    tip_InpSave:              string = "Save capture as image file"
    tip_InpCopy:              string = "Copy image to clipboard"
    tip_InpEdit:              string = "Open in sCapture editor"
    tip_InpClose:             string = "Cancel and discard capture"
    tip_InpDraw:              string = "Free draw tool"
    tip_InpLine:              string = "Draw straight line"
    tip_InpCircle:            string = "Draw circle or ellipse"
    tip_InpRect:              string = "Draw rectangle or square"
    tip_InpArrow:             string = "Draw arrow"
    tip_InpText:              string = "Add text annotation"
    tip_InpMarker:            string = "Highlight with marker"
    flt_Png:                  string = "PNG - Portable Network Graphics (*.png)"
    flt_Jpg:                  string = "JPG - JPEG Image (*.jpg)"
    flt_Bmp:                  string = "BMP - Windows Bitmap (*.bmp)"
    flt_Tga:                  string = "TGA - Truevision Targa (*.tga)"
}

private const FrenchStringsName = "lang/fr/scapture.tweak"
private const FrenchStrings = #include("../datas/lang/fr/scapture.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of sCapture in the active language.
func appStrings()->const &AppStrings => &g_AppStrings

// Registers the sCapture string table and its embedded translations.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "scapture")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
