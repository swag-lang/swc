// The main window once [[MainWnd.create]] has run. Headless fixtures that build a panel on its
// own leave it null.
var g_Main: *MainWnd?

const ClipboardFormat        = "Swag.Capture"
const CaptureFileMetadataTag = "Swag.Capture.File"
const IconsSvg               = #include("../datas/icons.svg")
const AppIcon                = #include("../datas/appicon.png")

// Interface metrics, taken from the application chart: a glyph never fills more than half
// of the cell it sits in, and the space left around it is what separates one control from
// the next. Nothing here is a container for a label stacked under an icon.
const RailLabelWidth  = 128.0     // Content width of a rail cell when the labels option puts a word beside the glyph.
const ReadoutWidth    = 88.0      // One machine readout of the command row.
const VerbsWidth      = 272.0     // The command group: two named application actions.
const ReadoutsWidth   = 240.0     // The readout group: both cells, their gap, and outer air.
const RightPanelWidth = 288.0     // Content width of the tool panel on the right.
const ToolTitleHeight = 26.0      // Heading included in the upper split panel.

// The editor tool, which decides what a drag on the capture creates.
enum EditMode { Shape, Arrow, Line, Polygon, Text, Favorites, Draw, Highlight, Selection, Step, Image, PixSel, Callout }

// Identifies a glyph of the application icon set (`datas/icons.svg`), in the grid
// order of the document. The set is rasterized on demand per size and scale through
// [[Gui.IconSet]], so every glyph stays sharp at any display density.
enum CaptureIcons
{
    Shape               // Shape tool.
    Line                // Line tool.
    Polygon             // Polygon tool.
    Arrow               // Arrow tool.
    Text                // Text tool.
    Favorites           // Quick-style favorites.
    Capture             // Capture trigger.
    Draw                // Free-hand draw tool.
    Library             // Capture library.
    Highlight           // Highlight tool.
    Select              // Selection tool.
    Step                // Numbered-step tool.
    Image               // Image effect.
    Blur                // Blur effect.
    Pixelate            // Pixelate effect.
    Zoom                // Zoom effect.
    PixSel              // Pixel-selection tool.
    Cube                // Capture-content effect.
    Circle              // Circle shape.
    Rect                // Rectangle outline shape.
    ViewSmall           // Small recent view.
    ViewMedium          // Medium recent view.
    ViewBig             // Big recent view.
    Calendar            // Library date grouping.
    Archive             // Library all-captures entry.
    Monitor             // Capture one monitor.
    FullScreen          // Capture the full screen.
    CaptureArea         // Capture a picked area.
    ActiveWindow        // Capture the active window.
    LastArea            // Capture the previous area again.
    SquareFill          // Filled badge square.
    TextAlignLeft       // Left text alignment.
    TextAlignCenter     // Centered text alignment.
    TextAlignRight      // Right text alignment.
    AlignTop            // Top vertical alignment.
    AlignMiddle         // Middle vertical alignment.
    AlignBottom         // Bottom vertical alignment.
    RatingStar          // Capture rating.
}

// The application icon document and the frames rasterized from it, shared by the main window
// and the headless test fixtures; parsed and rasterized once per process.
var g_CaptureIcons:       Gui.IconAtlas
var g_CaptureIconsParsed: bool

func captureIcons()->*Gui.IconAtlas
{
    if not g_CaptureIconsParsed
    {
        expect g_CaptureIcons.setup(cast(string, IconsSvg))
        g_CaptureIconsParsed = true
    }

    return &g_CaptureIcons
}

// The size of the thumbnails in the recent strip.
enum BottomSize
{
    Small
    Medium
    Big
}

// The application window: the menus and tool rail, the editor or the library, the recent strip,
// the quick styles, and the properties.
struct MainWnd
{
    using wnd: Wnd

    late
    {
        topBar, recentBar, rightBar, editBar: *Wnd
        toolRail, commandReadouts: *StackLayoutCtrl
        editWnd:                   *EditWnd
        quickWnd:                  *QuickWnd
        propWnd:                   *PropWnd
        libWnd:                    *LibraryWnd
        recentWnd:                 *RecentWnd
        quickStyleBar:             *SplitterCtrl
        toolTitle:                 *Label
        topMenu:                   *MenuCtrl
        libraryBtn, captureBtn:    *PushButton
        zoomBtn:                   *IconButton
        appearanceButton:          *AppearanceButton
    }

    sizeBtn:       *IconButton?
    embInfoFreeze: *InfoBar?
    icons:         IconSet
    appIcon:       ImageList
    monitors:      Array'Env.Monitor

    // State
    editMode:                                  EditMode   = .Shape
    bottomSize:                                BottomSize = .Medium
    pixSelFillCol:                             Color      = Argb.White
    inPlaceEdit, snap, freezeSel, libraryMode: bool
    firstShow:                                 bool       = true
    fileDlgState, fileDlgStateInPlace:         FileDlgState
    libraryFolderDlgState:                     FileDlgState
    exportFolderDlgState:                      FileDlgState
    libraryFolder:                             String
    captureOptions:                            CaptureOptions
    editorOptions:                             EditorOptions

    // Form models
    mdlFormShape:   FormShape
    mdlFormImage:   FormImage
    mdlFormStep:    FormStep
    mdlFormArrow:   FormArrow
    mdlFormLine:    FormLine
    mdlFormPolygon: FormPolygon
    mdlFormText:    FormText
    mdlFormDraw:    FormDraw
    mdlFormCallout: FormCallout

    // Set right after construction (create/test fixtures).
    late mdlHighlight, mdlPixSel, mdlFavorite: IForm

    // One interface per model field above, in FormRegistry order (see wrapper.swg)
    mdlByType: Array'IForm
}

impl IWnd for MainWnd
{
    mtd impl onSysUserEvent(evt: *SysUserEvent)
    {
        switch evt.kind
        {
        case .TrayIcon:
            if evt.trayAction == .Activate
            {
                with let surface = .surface!
                {
                    .show()
                    .bringToFront()
                }
            }
            elif evt.trayAction == .ContextMenu
            {
                .popupTrayMenu()
            }

        case .CustomMessage:
            if evt.messageId == OpenImageMessage and Clipboard.hasString() do
                .loadExternalImage(Clipboard.getString())
        }
    }

    // Takes an image dropped on the editor, from the desktop or from another application.
    //
    // Dropping a picture is the shortest way to open one, so it does exactly what the Open
    // command does — and a drag carrying several files opens one capture per file, which the
    // dialog cannot do at all. A drag that carries no file but carries a bitmap, the way an
    // image dragged out of a web page does, becomes a capture with nothing linked to it.
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        if not .hasDroppableImage(evt.data)
        {
            evt.accepted = false
            return
        }

        if evt.kind == .Drop do
            .openDroppedImages(evt.data)

        evt.effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
    }

    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        evt.accepted = false
        if evt.kind == .Close
        {
            evt.accepted = true
            .saveAppState()
            if .editorOptions.hideOnClose do
                .surface?.hide()
            else do
                .postCommandEvent(ActionGlobal.Exit)
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .saveAppState()
        .icons.free()
        .appIcon.release(.app().renderer)
    }

    mtd impl onStateEvent(evt: *StateEvent)
    {
        switch evt.kind
        {
        case .Init:

            // Runs while the window is still hidden, so restoring the persisted
            // size/position and loading content happens before the surface is
            // ever displayed (no black/empty flash on startup).
            .firstShow = false
            catch g_App.loadState()
            .createTopMenu()
            .surface?.constrainPositionToScreen(topLeft: true, margin: 10)
            .recentWnd.scheduleLoadRecent()
            evt.accepted = true

        case .Show:
            evt.accepted = true

        case .Hide:
            .saveAppState()
        }
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        if .inPlaceEdit do
            return

        catch
        {
            with evt.serializer
            {
                try .serialize("MainWnd.editMode", &me.editMode)
                try .serialize("MainWnd.snap", &me.snap)
                try .serialize("MainWnd.bottomSize", &me.bottomSize)
                try .serialize("MainWnd.fileDlgState", &me.fileDlgState)
                try .serialize("MainWnd.fileDlgStateInPlace", &me.fileDlgStateInPlace)
                try .serialize("MainWnd.libraryFolderDlgState", &me.libraryFolderDlgState)
                try .serialize("MainWnd.exportFolderDlgState", &me.exportFolderDlgState)
                try .serialize("MainWnd.libraryFolder", &me.libraryFolder)
                try .serialize("MainWnd.librarySortMethod", &me.libWnd.sortMethod)
                try .serialize("MainWnd.libraryInvertSort", &me.libWnd.invertSort)
                try .serialize("MainWnd.libraryPreviewSize", &me.libWnd.previewSize)
                try .serialize("MainWnd.libraryContentFilter", &me.libWnd.contentFilter)
                try .serialize("MainWnd.libraryFavoritesOnly", &me.libWnd.favoritesOnly)
                try .serialize("MainWnd.libraryMinimumRating", &me.libWnd.minimumRating)
                try .serialize("MainWnd.libraryApplicationFilter", &me.libWnd.applicationFilter)
                try .serialize("MainWnd.libraryTagFilter", &me.libWnd.tagFilter)
                try .serialize("MainWnd.libraryShowLinked", &me.libWnd.showLinkedImage)
                try .serialize("MainWnd.libraryShowUnlinked", &me.libWnd.showUnLinkedImage)
                try .serialize("MainWnd.libraryShowCurrentLinked", &me.libWnd.showUpToDateLinkedImage)
                try .serialize("MainWnd.libraryShowChangedLinked", &me.libWnd.showUnSavedLinkedImage)
                try .serialize("MainWnd.libraryShowRatingOverlay", &me.libWnd.showRatingOverlay)
                try .serialize("MainWnd.libraryShowLinkOverlay", &me.libWnd.showLinkOverlay)
                try .serialize("MainWnd.RightBar.Pane0", &me.quickStyleBar.items[0]!.size)
                try .serialize("MainWnd.RightBar.Pane1", &me.quickStyleBar.items[1]!.size)
                try .serialize("MainWnd.captureOptions", &me.captureOptions)
                try .serialize("MainWnd.editorOptions", &me.editorOptions)
            }
        }

        if evt.serializer.isReading()
        {
            // Migrate the only legacy matte value: it used to be the default, before
            // transparent came to mean "follow the active palette".
            .migrateStoredOptions()

            if not .libraryFolder.isEmpty() do
                discard catch g_Library.setFolder(.libraryFolder)
            .setTheme()
            .setLanguage()
            .quickStyleBar.sendResizeEvent()
            .setBottomSize(.bottomSize, animated: false)
            .setToolRailWidth()
            .updateState()
        }
    }

    mtd impl onFrameEvent(evt: *FrameEvent)
    {
        if evt.firstFrame do
            .quickWnd.setDefault()
    }
}

impl MainWnd
{
    // Opens the notification-area menu at the pointer, on a top-most surface of its own: the
    // main window may be hidden when the tray icon is clicked.
    mtd popupTrayMenu()
    {
        let sf = expect .app().createSurface(500, 400, 300, 300, .ToolWindow | .TopMost)

        with let menu = Wnd.create'MenuCtrl(sf.wnd.view)
        {
            .addItem(ActionGlobal.ShowEditor)
            .addSeparator()
            .addItem(ActionCapture.Area)
            .addItem(ActionCapture.LastArea)
            .addItem(ActionCapture.FullScreen)
            .addItem(ActionCapture.ActiveWnd)

            for idx in me.monitors.count do
                .addItem(ActionCapture.screenId(idx))

            .addSeparator()
            .addItem(ActionGlobal.Exit)
            .owner = me
            .setFramePainting(true)
            .dockStyle = .Center
            .padding   = 10
            .updateState()
            .computeLayoutPopup()
        }

        // The menu layout is logical; the surface rectangle is physical screen pixels.
        let pt         = Input.mousePosition()
        let shadowSize = .themeMetrics().surfaceWnd_ShadowSize
        menu.position.width  += 2 * shadowSize
        menu.position.height += 2 * shadowSize
        sf.setPosition({pt.x, pt.y, menu.position.width * sf.dpiScale, menu.position.height * sf.dpiScale})
        sf.constrainPositionToScreen()
        sf.wnd.view.backgroundStyle = .Window

        sf.show()
        sf.bringToFront()
        while not menu.isModalEnded() do
            .app().runFrame()
        sf.hide()
        if menu.modalResult() do
            .postCommandEvent(menu.modalResult())
        sf.destroy()
    }

    // Migrates values whose historical default would otherwise pin an old visual choice
    // forever. User-picked colors are left untouched.
    mtd migrateStoredOptions()
    {
        if cast(u32, .editorOptions.theme) > cast(u32, AppearanceTheme.Dark) do
            .editorOptions.theme = .SwagDark
        if .editorOptions.editBackColor == 0xFF2E2E2E'u32 do
            .editorOptions.editBackColor = 0
    }

    mtd saveAppState()
    {
        if not .firstShow do
            catch g_App.saveState()
    }

    mtd saveCapture(capture: *Capture)
    {
        // An automatic save may still be writing; land it first so its outcome is
        // reported and the two writes cannot interleave.
        .flushCaptureSave()
        catch capture.save() else do
            MessageDlg.error(.surface!, Format.toString(appStrings().msg_FailedSaveCapture, capture.file))
    }

    // Waits for the background save targeting `file` (any when null) and reports its
    // failure, which the timer that scheduled it can no longer do.
    mtd flushCaptureSave(file: string? = null)
    {
        let failed = g_CaptureSaves.flush(file)
        if not failed.isEmpty() do
            MessageDlg.error(.surface!, Format.toString(appStrings().msg_FailedSaveCapture, failed))
    }

    // Changes the user-defined name of a capture and persists it. The library shows
    // previews loaded without the background image, so that in-memory copy is never
    // saved (it would wipe the picture): the real file on disk is updated instead, then
    // the preview's displayed title.
    mtd setCaptureTitle(file: String, title: String)
    {
        let editCapture = .editWnd.getCapture()
        if editCapture and editCapture.file == file
        {
            editCapture.title   = title
            editCapture.changed = true
            .saveCapture(editCapture)
        }
        else
        {
            // The edited capture autosaves in the background; make sure this load
            // reads the latest landed version of the file.
            .flushCaptureSave(file)

            catch
            {
                let loaded = try Capture.load(file)
                defer Memory.delete(loaded)
                loaded.title   = title
                loaded.changed = true
                .saveCapture(loaded)
            } as err
            if err != null
            {
                MessageDlg.error(.surface!, appStrings().msg_FailedRename, err)
                return
            }
        }

        // Reflect the new title on the library preview(s) that reference this file.
        if .libWnd != null and .libWnd.view != null
        {
            for it in .libWnd.view.items where it.capture and it.fi.fullName == file do
                it.capture.title = title
            .libWnd.view.invalidate()
        }
    }

    // Renders a stored capture at full resolution and places it on the clipboard. Used
    // from the library, where the focused capture is only a lightweight preview: the
    // complete file is loaded, composited through the editor's render context, and
    // discarded without touching the active editor selection.
    mtd copyLibraryImage(file: String)
    {
        Cursor.activateWait()
        .flushCaptureSave(file)
        catch
        {
            let loaded = try Capture.load(file)
            defer Memory.delete(loaded)
            loaded.editView = .editWnd.editView
            Clipboard.addImage(loaded.toImage())
        } as err
        if err != null do
            MessageDlg.error(.surface!, appStrings().msg_FailedCopyImage, err)
    }

    // Opens the image file `arg`: the capture it was exported from when Swag Capture wrote it,
    // otherwise a new capture linked to the file.
    mtd loadExternalImage(arg: String)
    {
        let imgToLoad = catch Image.load(arg) as err
        if err != null
        {
            MessageDlg.error(.surface!, Format.toString(appStrings().msg_FailedLoadFile, arg), err)
            return
        }

        // A picture Swag Capture exported names the capture it came from: open that one instead.
        var done = false
        for md in imgToLoad.metadata where md.isTag(CaptureFileMetadataTag)
        {
            catch { Memory.delete(try .recentWnd.addRecent(cast(string, md.toSlice()), true, true)) }
            done = true
            break
        }

        if not done do
            .newCapture(imgToLoad, arg)

        if .libraryMode
        {
            .swapLibraryMode()
            .updateState()
        }

        .surface?.bringToFront()
    }

    // Returns the tool the editor acts as: the active one, or under the selection tool, the one
    // the selected forms belong to.
    mtd getEditMode()->EditMode
    {
        switch .editMode
        {
        case .Selection:
            .editMode = .Shape
            .getCapture()?.updateEditModeFromSelection()
            let edMode = .editMode
            .editMode = .Selection
            return edMode

        case .Favorites:
            return formToEditMode(.mdlFavorite)

        case .Highlight:
            return formToEditMode(.mdlHighlight)

        case .PixSel:
            return formToEditMode(.mdlPixSel)
        }

        return .editMode
    }

    // Freezes the forms the capture holds now, so the mouse only reaches forms drawn after them,
    // and shows a bar saying so; or thaws them again.
    mtd freezeSelection(freeze: bool)
    {
        if not freeze and .embInfoFreeze
        {
            .embInfoFreeze.destroy()
            .embInfoFreeze = null
            .freezeSel     = false
        }
        elif freeze and not .embInfoFreeze
        {
            // Nothing to freeze without a capture (the Freeze command is disabled in
            // that case, but guard here too so no code path can fault on getCapture()).
            let capture = .getCapture()
            if not capture do
                return

            .embInfoFreeze = InfoBar.create(.editWnd.view, appStrings().ui_Frozen, .Message, flags: .Bottom)
            .embInfoFreeze.sigDismissed += func|main = me|(_)
            {
                main.freezeSel     = false
                main.embInfoFreeze = null
            }

            capture.selection.clear()
            capture.selectionHasChanged()
            .freezeSel = true

            for it in capture.forms do
                (assume cast(*BaseForm, it)).freeze = true
        }
    }

    mtd updateState()
    {
        .updateCommandState()
        .updateToolTitle()
        if .propWnd != null do
            .propWnd.selectionHasChanged()
        if .quickWnd != null do
            .quickWnd.updateQuickStyles()
    }

    mtd captureHasChanged()
    {
        .updateSizeDisplay()
        if .recentWnd != null
        {
            if .toolRail != null do
                .toolRail.updateCommandState()
            .updateRecent()
        }
    }

    mtd getCapture()->*Capture?
    {
        if .libraryMode do
            return .libWnd.getCapture()
        return .editWnd.getCapture()
    }

    mtd updateRecent()
    {
        if .recentWnd != null do
            .recentWnd.updateRecent()
    }

    // The two readouts of the command row. Both are machine data, set in the fixed-width
    // theme family, so a value never changes the width of the control that holds it.
    mtd updateZoomDisplay()
    {
        // The percent sign is appended rather than formatted: '%' is the placeholder itself.
        var label = Format.toString("%", cast(s32, .editWnd.editView.zoom * 100))
        label         += "%"
        .zoomBtn.name = label
        .zoomBtn.invalidate()
    }

    mtd updateSizeDisplay()
    {
        if not .sizeBtn do
            return

        let capture = .getCapture()
        if capture do
            .sizeBtn.name = Format.toString("%×%", capture.width, capture.height)
        else do
            .sizeBtn.name = "—"
        .sizeBtn.invalidate()
    }

    // Names the surface the right column is editing. A pane title would only repeat what the
    // reader already sees; the tool name says something the panel itself does not.
    mtd updateToolTitle()
    {
        if .toolTitle == null do
            return

        var name = appStrings().act_Select
        switch .getEditMode()
        {
        case .Shape:     name = appStrings().act_Shape
        case .Arrow:     name = appStrings().act_Arrow
        case .Line:      name = appStrings().act_Line
        case .Polygon:   name = appStrings().act_Polygon
        case .Text:      name = appStrings().act_Text
        case .Callout:   name = appStrings().act_Callout
        case .Draw:      name = appStrings().act_Draw
        case .Highlight: name = appStrings().act_Highlight
        case .Step:      name = appStrings().act_Step
        case .Image:     name = appStrings().ui_MenuImage
        case .PixSel:    name = appStrings().act_PixSel
        case .Favorites: name = appStrings().act_Favorites
        default:         break
        }

        .toolTitle.setText(String.toUpper(name))
    }

    // Registers every command family of the editor.
    mtd registerActions()
    {
        .registerAction'ActionMoveSel()
        .registerAction'ActionUndo()
        .registerAction'ActionCaptureDelay()
        .registerAction'ActionPixSel()
        .registerAction'ActionCapture()
        .registerAction'ActionAlign()
        .registerAction'ActionGroup()
        .registerAction'ActionToolMode()
        .registerAction'ActionCopyPaste()
        .registerAction'ActionFile()
        .registerAction'ActionZoom()
        .registerAction'ActionImage()
        .registerAction'ActionSelection()
        .registerAction'ActionFlatten()
        .registerAction'ActionRecentSize()
        .registerAction'ActionQuickStyle()
        .registerAction'ActionEdit()
        .registerAction'ActionGlobal()
        .registerAction'ActionAbout()
        .registerAction'ActionOptions()
        .registerAction'ActionView()
    }

    // Binds the keyboard shortcuts of the editor to their commands.
    mtd registerShortcuts()
    {
        // Standard shortcuts
        .registerKeyShortcut(.Control, .C, ActionCopyPaste.Copy)
        .registerKeyShortcut(.Control, .X, ActionCopyPaste.Cut)
        .registerKeyShortcut(.Control, .V, ActionCopyPaste.Paste)
        .registerKeyShortcut(.Control, .Insert, ActionCopyPaste.Copy)
        .registerKeyShortcut(.Shift, .Insert, ActionCopyPaste.Paste)
        .registerKeyShortcut(.Control, .Z, ActionUndo.DoUndo)
        .registerKeyShortcut(.Control, .Y, ActionUndo.DoRedo)
        .registerKeyShortcut(.None, .Delete, ActionSelection.DeleteSelection)
        .registerKeyShortcut(.CtrlShift, .A, ActionCopyPaste.CopyAsImage)
        .registerKeyShortcut(.Control, .Space, ActionSelection.Freeze)
        .registerKeyShortcut(.Control, .A, ActionSelection.SelectAll)
        .registerKeyShortcut(.Control, .D, ActionSelection.DeSelectAll)
        .registerKeyShortcut(.CtrlShift, .D, ActionFile.DupCapture)
        .registerKeyShortcut(.CtrlShift, .I, ActionSelection.InvertSelection)
        .registerKeyShortcut(.CtrlShift, .T, ActionFlatten.FlattenAll)
        .registerKeyShortcut(.Alt, .F4, ActionGlobal.Exit)
        .registerKeyShortcut(.Control, .N, ActionFile.NewImage)
        .registerKeyShortcut(.CtrlShift, .N, ActionFile.NewFromClipboard)
        .registerKeyShortcut(.CtrlShift, .S, ActionFile.SaveAsImage)
        .registerKeyShortcut(.Control, .S, ActionFile.UpdateLinkedImage)
        .registerKeyShortcut(.Control, .O, ActionFile.OpenImage)
        .registerKeyShortcut(.None, .F2, ActionEdit.EditText)
        .registerKeyShortcut(.CtrlAlt, .O, ActionOptions.Options)
        .registerKeyShortcut(.Control, .G, ActionGroup.Group)
        .registerKeyShortcut(.CtrlShift, .G, ActionGroup.Ungroup)
        .registerKeyShortcut(.None, .Home, ActionAlign.SendToFront)
        .registerKeyShortcut(.None, .End, ActionAlign.SendToBack)
        .registerKeyShortcut(.None, .PageUp, ActionAlign.MoveForward)
        .registerKeyShortcut(.None, .PageDown, ActionAlign.MoveBackward)
        .registerKeyShortcut(.Shift, .Left, ActionMoveSel.Left1)
        .registerKeyShortcut(.Shift, .Up, ActionMoveSel.Top1)
        .registerKeyShortcut(.Shift, .Right, ActionMoveSel.Right1)
        .registerKeyShortcut(.Shift, .Down, ActionMoveSel.Bottom1)
        .registerKeyShortcut(.None, .Left, ActionMoveSel.Left)
        .registerKeyShortcut(.None, .Up, ActionMoveSel.Top)
        .registerKeyShortcut(.None, .Right, ActionMoveSel.Right)
        .registerKeyShortcut(.None, .Down, ActionMoveSel.Bottom)
        .registerKeyShortcut(.Control, .Add, ActionZoom.ZoomIn)
        .registerKeyShortcut(.Control, .Subtract, ActionZoom.ZoomOut)
        .registerKeyShortcut(.Control, .NumPad0, ActionZoom.Zoom1)

        var errorReg = false

        #[Swag.Mixin]
        mtd registerHotKey(modifiers: Input.KeyModifiers, key: Input.Key, wndId: WndId)
        {
            catch .app().registerHotKey(modifiers, key, wndId, me) else
            {
                if not errorReg
                {
                    var msg = Format.toString(appStrings().msg_ShortcutTaken, Input.formatKeyShortcut(modifiers, key))
                    msg += appStrings().msg_ShortcutTakenWhy
                    discard InfoBar.create(.editWnd!, msg, .Critical)
                }

                errorReg = true
            }
        }

        .registerHotKey(.None, .PrintScreen, ActionCapture.Area)
        .registerHotKey(.CtrlShift, .PrintScreen, ActionCapture.LastArea)
        .registerHotKey(.Control, .PrintScreen, ActionCapture.FullScreen)
        .registerHotKey(.Alt, .PrintScreen, ActionCapture.ActiveWnd)
    }

    mtd setTheme()
    {
        .appearanceButton.setAppearanceTheme(.editorOptions.theme)

        // Pixel-selection forms borrow a theme color, so their retained renderings
        // follow the switch.
        if .editWnd != null do
            .editWnd.getCapture()?.invalidateAllFormCaches()
    }

    // Applies the language selected in the options to every string table.
    //
    // The tables always resolve, so a failure can only be an incomplete installation;
    // the interface then simply stays on the reference English wording.
    mtd setLanguage()
    {
        var tag: string = Gui.ReferenceLanguage
        switch #complete .editorOptions.language
        {
        case .System:  tag = ""
        case .French:  tag = "fr"
        case .English: break
        }

        discard catch .appearanceButton.setAppearanceLanguage(tag)
    }

    // Creates an icon descriptor for an application glyph at `size` logical pixels.
    mtd icon(idx: CaptureIcons, size = 0.0)->Icon
    {
        let resolvedSize = size ? size : themeActionIconSize(.themeMetrics())
        return .icons.icon(cast(s32, idx), resolvedSize, .theme().res.atlasScale)
    }

    // Builds the main window: the command row, the tool rail, the editor, the recent strip,
    // and the tool panel, with the library hidden behind them until it is asked for.
    func create(parent: *Wnd)->*MainWnd
    {
        let srf = parent.surface!
        srf.minSize = {1024, 512}

        var imgApp: Image
        #static if #command == Swag.CompilerCommand.Test do
            imgApp = Image.create(512, 512, .RGBA8)
        else do
            imgApp = expect Image.decode(".png", AppIcon)

        let renderer = parent.app().renderer

        with let result = Wnd.create'MainWnd(parent, "capture.mainwnd")
        {
            result.surface!.setView(result)
            .icons.setup(renderer, captureIcons())
            .appIcon.set(renderer.addImage(imgApp))
            .backgroundStyle = .Window
            .mdlFavorite     = &result.mdlFormShape
            .mdlHighlight    = &result.mdlFormShape
            .mdlPixSel       = &result.mdlFormShape
            .monitors        = Env.getMonitors()
        }

        result.createAppearanceButton()

        // One Voltage rail identifies every standard Swag application surface.
        Separator.create(result, .Top, .Accent)

        result.createCommandRow()
        result.createToolRail()
        result.createEditArea()
        result.createRecentBar()
        result.createToolPanel()

        with result
        {
            // Theme and language come before anything is built from a string. A first run has
            // no persisted state to read them from, and would otherwise stay on the reference
            // English wording whatever the locale.
            .setTheme()
            .setLanguage()
            .registerActions()
            .registerShortcuts()
            .updateZoomDisplay()
            .updateSizeDisplay()
            .setBottomSize(.Medium, animated: false)
            .setToolRailWidth()
            .updateState()
            .libWnd = LibraryWnd.create(result)
            .libWnd.hide()
        }

        g_Main = result
        return result
    }
}
