// Global variable
var g_Main: #null *MainWnd

// Constants
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

// Enums
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
    if !g_CaptureIconsParsed
    {
        expect g_CaptureIcons.setup(cast(string) IconsSvg)
        g_CaptureIconsParsed = true
    }

    return &g_CaptureIcons
}

enum BottomSize
{
    Small
    Medium
    Big
}

// Main structure
struct MainWnd
{
    using wnd: Wnd
    #[Swag.Late]
    {
        topBar, recentBar, rightBar, editBar: *Wnd
        toolRail, commandReadouts:            *StackLayoutCtrl
        editWnd:                              *EditWnd
        quickWnd:                             *QuickWnd
        propWnd:                              *PropWnd
        libWnd:                               *LibraryWnd
        recentWnd:                            *RecentWnd
        quickStyleBar:                        *SplitterCtrl
        toolTitle:                            *Label
        topMenu:                              *MenuCtrl
        libraryBtn, captureBtn:               *PushButton
        zoomBtn:                              *IconButton
        appearanceButton:                     *AppearanceButton
    }

    sizeBtn:       #null *IconButton
    embInfoFreeze: #null *InfoBar
    icons:         IconSet
    appIcon:       ImageList
    monitors:      Array'Env.Monitor

    // State
    editMode:                                  EditMode   = .Shape
    bottomSize:                                BottomSize = Medium
    pixSelFillCol:                             Color      = Argb.White
    inPlaceEdit, snap, freezeSel, libraryMode: bool
    firstShow = true
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
    #[Swag.Late]
    mdlHighlight, mdlPixSel, mdlFavorite: IForm

    // One interface per model field above, in FormRegistry order (see wrapper.swg)
    mdlByType: Array'IForm
}

// Interface implementation
impl IWnd for MainWnd
{
    mtd popupBar()
    {
        let sf        = (catch .app().createSurface(500, 400, 300, 300, .ToolWindow | .TopMost))!
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
        while !menu.isModalEnded() do
            .app().runFrame()
        sf.hide()
        if menu.modalResult() do
            .postCommandEvent(menu.modalResult())
        sf.destroy()
    }

    mtd impl onSysUserEvent(evt: *SysUserEvent)
    {
        switch evt.kind
        {
        case .TrayIcon:
            if evt.trayAction == .Activate
            {
                let srf = .surface!
                srf.show()
                srf.bringToFront()
            }
            elif evt.trayAction == .ContextMenu do
                .popupBar()

        case .CustomMessage:
            if evt.messageId == 1 and Clipboard.hasString() do
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
        if !.hasDroppableImage(evt.data)
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

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .saveAppState()
        let renderer = .app().renderer
        .icons.free()
        .appIcon.release(renderer)
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
                .serialize("MainWnd.editMode", &me.editMode)
                .serialize("MainWnd.snap", &me.snap)
                .serialize("MainWnd.bottomSize", &me.bottomSize)
                .serialize("MainWnd.fileDlgState", &me.fileDlgState)
                .serialize("MainWnd.fileDlgStateInPlace", &me.fileDlgStateInPlace)
                .serialize("MainWnd.libraryFolderDlgState", &me.libraryFolderDlgState)
                .serialize("MainWnd.exportFolderDlgState", &me.exportFolderDlgState)
                .serialize("MainWnd.libraryFolder", &me.libraryFolder)
                .serialize("MainWnd.librarySortMethod", &me.libWnd.sortMethod)
                .serialize("MainWnd.libraryInvertSort", &me.libWnd.invertSort)
                .serialize("MainWnd.libraryPreviewSize", &me.libWnd.previewSize)
                .serialize("MainWnd.libraryContentFilter", &me.libWnd.contentFilter)
                .serialize("MainWnd.libraryFavoritesOnly", &me.libWnd.favoritesOnly)
                .serialize("MainWnd.libraryMinimumRating", &me.libWnd.minimumRating)
                .serialize("MainWnd.libraryApplicationFilter", &me.libWnd.applicationFilter)
                .serialize("MainWnd.libraryTagFilter", &me.libWnd.tagFilter)
                .serialize("MainWnd.libraryShowLinked", &me.libWnd.showLinkedImage)
                .serialize("MainWnd.libraryShowUnlinked", &me.libWnd.showUnLinkedImage)
                .serialize("MainWnd.libraryShowCurrentLinked", &me.libWnd.showUpToDateLinkedImage)
                .serialize("MainWnd.libraryShowChangedLinked", &me.libWnd.showUnSavedLinkedImage)
                .serialize("MainWnd.libraryShowRatingOverlay", &me.libWnd.showRatingOverlay)
                .serialize("MainWnd.libraryShowLinkOverlay", &me.libWnd.showLinkOverlay)
                .serialize("MainWnd.RightBar.Pane0", &me .quickStyleBar.items[0]!.size)
                .serialize("MainWnd.RightBar.Pane1", &me .quickStyleBar.items[1]!.size)
                .serialize("MainWnd.captureOptions", &me.captureOptions)
                .serialize("MainWnd.editorOptions", &me.editorOptions)
            }
        }

        if evt.serializer.isReading()
        {
            // Migrate the only legacy matte value: it used to be the default, before
            // transparent came to mean "follow the active palette".
            .migrateStoredOptions()

            if !.libraryFolder.isEmpty() do
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

// Main implementation
impl MainWnd
{
    // Migrates values whose historical default would otherwise pin an old visual choice
    // forever. User-picked colors are left untouched.
    mtd migrateStoredOptions()
    {
        if cast(u32) .editorOptions.theme > cast(u32) AppearanceTheme.Dark do
            .editorOptions.theme = .SwagDark
        if .editorOptions.editBackColor == 0xFF2E2E2E'u32 do
            .editorOptions.editBackColor = 0
    }

    mtd saveAppState()
    {
        if !.firstShow do
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
    mtd flushCaptureSave(file: #null string = null)
    {
        let failed = g_CaptureSaves.flush(file)
        if !failed.isEmpty() do
            MessageDlg.error(.surface!, Format.toString(appStrings().msg_FailedSaveCapture, failed))
    }

    // Change the user-defined name of a capture and persist it. The library shows
    // previews loaded without the background image, so we never save that in-memory
    // copy (it would wipe the picture); we update the real file on disk instead and
    // then refresh the preview's displayed title.
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

            let full: #null *Capture = catch Capture.load(file) as err
            if err != null
            {
                MessageDlg.error(.surface!, appStrings().msg_FailedRename, err)
                return
            }

            let loaded = full!
            loaded.title   = title
            loaded.changed = true
            .saveCapture(loaded)
            Memory.delete(loaded)
        }

        // Reflect the new title on the library preview(s) that reference this file.
        if Swag.isSet(.libWnd) and Swag.isSet(.libWnd.view)
        {
            for it in .libWnd.view.items where it.capture and it.fi.fullname == file do
                it.capture.title = title
            .libWnd.view.invalidate()
        }
    }

    // Render a stored capture at full resolution and place it on the clipboard. Used
    // from the library, where the focused capture is only a lightweight preview: we
    // load the complete file, borrow the editor's render context to composite it, and
    // discard it without touching the active editor selection.
    mtd copyLibraryImage(file: String)
    {
        Cursor.activateWait()
        .flushCaptureSave(file)
        let full: #null *Capture = catch Capture.load(file) as err
        if err != null
        {
            MessageDlg.error(.surface!, appStrings().msg_FailedCopyImage, err)
            return
        }

        let loaded = full!
        loaded.editView = .editWnd.editView
        Clipboard.addImage(loaded.toImage())

        Memory.delete(loaded)
    }

    mtd loadExternalImage(arg: String)
    {
        let imgToLoad = catch Image.load(arg) as err
        if err != null
        {
            MessageDlg.error(.surface!, Format.toString(appStrings().msg_FailedLoadFile, arg), err)
            return
        }

        var done = false
        for md in imgToLoad.metadata
        {
            if md.isTag(CaptureFileMetadataTag)
            {
                let dupCapture = catch .recentWnd.addRecent(cast(string) md.toSlice(), true, true)
                Memory.delete(dupCapture)
                done = true
                break
            }
        }

        if !done do
            .newCapture(imgToLoad, arg)

        if .libraryMode
        {
            .swapLibraryMode()
            .updateState()
        }

        .surface?.bringToFront()
    }

    mtd getEditMode()->EditMode
    {
        switch .editMode
        {
        case .Selection:
            .editMode = .Shape
            let capture = .getCapture()
            if capture do
                capture.updateEditModeFromSelection()
            let edMode = .editMode
            .editMode = .Selection
            return edMode

        case .Favorites:
            return formToEditMode(.mdlFavorite!)

        case .Highlight:
            return formToEditMode(.mdlHighlight!)

        case .PixSel:
            return formToEditMode(.mdlPixSel!)
        }

        return .editMode
    }

    mtd freezeSelection(freeze: bool)
    {
        if !freeze and .embInfoFreeze
        {
            .embInfoFreeze.destroy()
            .embInfoFreeze = null
            .freezeSel     = false
        }
        elif freeze and !.embInfoFreeze
        {
            // Nothing to freeze without a capture (the Freeze command is disabled in
            // that case, but guard here too so no code path can fault on getCapture()).
            let capture = .getCapture()
            if !capture do
                return

            .embInfoFreeze              = InfoBar.create(.editWnd.view!, appStrings().ui_Frozen, .Message, flags: .Bottom)
            .embInfoFreeze.sigDismissed += func|main = me|(ctrl)
            {
                main.freezeSel     = false
                main.embInfoFreeze = null
            }

            capture.selection.clear()
            capture.selectionHasChanged()
            .freezeSel = true

            for it in capture.forms
            {
                let p = cast(*BaseForm) it.buffer
                p.freeze = true
            }
        }
    }

    mtd updateState()
    {
        .updateCommandState()
        .updateToolTitle()
        if Swag.isSet(.propWnd) do
            .propWnd.selectionHasChanged()
        if Swag.isSet(.quickWnd) do
            .quickWnd.updateQuickStyles()
    }

    mtd captureHasChanged()
    {
        .updateSizeDisplay()
        if Swag.isSet(.recentWnd)
        {
            if Swag.isSet(.toolRail) do
                .toolRail.updateCommandState()
            .updateRecent()
        }
    }

    mtd getCapture()->#null *Capture
    {
        if .libraryMode do
            return .libWnd.getCapture()
        return .editWnd.getCapture()
    }

    mtd updateRecent()
    {
        if Swag.isSet(.recentWnd) do
            .recentWnd.updateRecent()
    }

    // The two readouts of the command row. Both are machine data, set in the fixed-width
    // theme family, so a value never changes the width of the control that holds it.
    mtd updateZoomDisplay()
    {
        let z   = cast(s32) (.editWnd.editView.zoom * 100)
        var txt = Format.toString("%", z)
        txt           += "%"
        .zoomBtn.name = txt
        .zoomBtn.invalidate()
    }

    mtd updateSizeDisplay()
    {
        if !.sizeBtn do
            return

        let capture = .getCapture()
        if capture do
            .sizeBtn.name = Format.toString("%×%", capture.width, capture.height)
        else do
            .sizeBtn.name = "—"
        .sizeBtn.invalidate()
    }

    // Names the surface the right column is editing. It replaces the two pane titles the
    // panel used to carry, and unlike them it says something the reader does not know.
    mtd updateToolTitle()
    {
        if !Swag.isSet(.toolTitle) do
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

        let upper = String.toUpper(name)
        .toolTitle.setText(upper.toString())
    }

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
                if !errorReg
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

    mtd createTopMenu()
    {
        Swag.assert(me.parent != null)
        let parentWnd = me.parent
        let metrics   = .themeMetrics()
        with .topMenu = MenuCtrl.createBar(parentWnd, owner: me)
        {
            .sendToBack()
            .position.height = Math.max(.position.height, parentWnd.padding.y)
            .preferredSize.y = .position.height
            .dockStyle       = .Top
            .margin.y        = -parentWnd.padding.y
            .backgroundStyle = .Transparent

            // The bar rides inside the caption, which carries the application mark on its
            // leading edge: the first menu starts past the mark instead of over it.
            .padding.x = metrics.wnd_CaptionMarginTitle + metrics.wnd_CaptionIconSize + metrics.menuBar_SpaceBetween * 0.5
        }

        // File menu
        with let fileMenu = MenuCtrl.createPopup(me.parent, owner: me)
        {
            .addGroup([ActionFile.NewImage, ActionFile.NewFromClipboard])
            .addGroup([ActionFile.OpenImage, ActionFile.SaveAsImage])
            .addGroup([ActionFile.SaveAsLinkedImage, ActionFile.UpdateLinkedImage, ActionFile.UnlinkImage])
            .addGroup([ActionFile.FileDetails])
            .addItems([ActionGlobal.Minimize, ActionGlobal.Exit])
            topMenu.addPopup(func()->string => appStrings().ui_MenuFile, fileMenu)
        }

        // Capture menu
        with let captureMenu = MenuCtrl.createPopup(me.parent, owner: me)
        {
            .addItems([ActionCapture.Area, ActionCapture.LastArea, ActionCapture.FullScreen, ActionCapture.ActiveWnd])

            for idx in me.monitors.count do
                .addItem(ActionCapture.screenId(idx))

            .addSeparator()
            .addItem(ActionCapture.HideEditor)
            .addItem(ActionCapture.CaptureCursor)

            with let delayMenu = MenuCtrl.createPopup(captureMenu, owner: me)
            {
                .addGroup([ActionCaptureDelay.Delay0])
                .addItems([ActionCaptureDelay.Delay1, ActionCaptureDelay.Delay2, ActionCaptureDelay.Delay5, ActionCaptureDelay.Delay9])
                captureMenu.addPopup(delayMenu, ActionCaptureDelay.Delay)
            }

            topMenu.addPopup(func()->string => appStrings().ui_MenuCapture, captureMenu)

            .addSeparator()
            .addItems([ActionCapture.ToInPlace, ActionCapture.ToEditor, ActionCapture.ToClipboard])
        }

        // Edit menu
        with let editMenu = MenuCtrl.createPopup(me.parent, owner: me)
        {
            .addGroup([ActionUndo.DoUndo, ActionUndo.DoRedo])
            .addGroup([ActionCopyPaste.Copy, ActionCopyPaste.Cut, ActionCopyPaste.Paste])
            .addGroup([ActionSelection.SelectAll, ActionSelection.SelectSameAll, ActionSelection.DeSelectAll, ActionSelection.InvertSelection])
            .addGroup([ActionGroup.Group, ActionGroup.Ungroup])
            .addGroup([ActionEdit.ResetRotation])
            .addGroup([ActionSelection.Freeze])
            .addItems([ActionSelection.Snap])
            topMenu.addPopup(func()->string => appStrings().ui_MenuEdit, editMenu)
        }

        // Image menu
        with let imageMenu = MenuCtrl.createPopup(me.parent, owner: me)
        {
            .addGroup([ActionCopyPaste.CopyAsImage])
            .addGroup([ActionImage.RestoreOrg])
            .addGroup([ActionImage.ResizeImage, ActionImage.ExpandImage, ActionImage.ExpandCapture, ActionImage.TrimCapture])
            .addGroup([ActionFlatten.FlattenAll])
            .addItems([ActionImage.FlipImage, ActionImage.MirrorImage, ActionImage.RotateImageRight, ActionImage.RotateImageLeft])
            topMenu.addPopup(func()->string => appStrings().ui_MenuImage, imageMenu)
        }

        // View menu. The recent-preview size lives here now, instead of on three radio
        // buttons standing permanently beside the recent bar.
        with let viewMenu = MenuCtrl.createPopup(me.parent, owner: me)
        {
            .addGroup([ActionZoom.ZoomIn, ActionZoom.ZoomOut])
            .addGroup([ActionZoom.Zoom1, ActionZoom.ZoomFit])
            .addGroup([ActionRecentSize.RecentSmall, ActionRecentSize.RecentMedium, ActionRecentSize.RecentBig])
            .addItems([ActionView.Clip])
            topMenu.addPopup(func()->string => appStrings().ui_MenuView, viewMenu)
        }

        // Help menu
        with let helpMenu = MenuCtrl.createPopup(me.parent, owner: me)
        {
            .addItem(ActionOptions.Options)
            topMenu.addPopup(func()->string => appStrings().ui_MenuHelp, helpMenu)
        }
    }

    // Speech-bubble glyph drawn for the Callout toolbar button: the icon sheet has no
    // sprite for this tool, so it paints its own rounded body plus a small tail. Its round
    // corners are deliberate — the glyph depicts a shape the user draws, not chrome.
    func drawCalloutGlyph(btn: *IconButton, bc: *PaintContext, pos: Math.Rectangle, flags: PaintItemFlags)
    {
        bc.painter.setParams(.Antialiased)
        let col = btn.isChecked ? btn.themeColors().btnIcon_CheckedIcon : btn.themeColors().btnIcon_Icon

        // A custom painter is handed the whole content rectangle, not the icon extent, so
        // the glyph places itself where a sprite of the set would have landed: centered
        // when the cell shows no label, against the leading edge when it does.
        let glyphSize = themeActionIconSize(btn.themeMetrics())
        var box       = Math.Rectangle{pos.x, pos.vertCenter() - glyphSize * 0.5, glyphSize, glyphSize}
        if btn.flags.has(.IconOnly) or btn.name.isEmpty() do
            box.x = pos.horzCenter() - glyphSize * 0.5

        // The sprites of the set stand on roughly three fifths of their box; the bubble
        // matches that weight so the rail reads as one column of glyphs.
        var body = box
        body.inflate(-box.width * 0.20, -box.height * 0.20)
        body.height *= 0.70

        let tx = body.x + body.width * 0.28
        var tail: LinePath
        tail.start(tx, body.bottom() - 1)
        tail.lineTo(tx + body.width * 0.30, body.bottom() - 1)
        tail.lineTo(tx, body.bottom() + box.height * 0.20)
        tail.close()
        bc.painter.fillPolygon(&tail, col)

        bc.painter.fillRoundRect(body, 3, 3, col)
    }

    // The tools stand in a column against the window's left edge, one square cell each,
    // glyph only. A horizontal ribbon of labelled tiles across the top costs a whole row
    // of height, pushes the canvas down, and sends the eye across the window to change
    // tool; the rail sits where the pointer already is.
    mtd createToolRail()
    {
        let metrics     = .themeMetrics()
        let cellSize    = themeActionButtonSize(metrics)
        let glyphSize   = themeActionIconSize(metrics)
        let cellPadding = (cellSize - glyphSize) * 0.5
        with me.toolRail = StackLayoutCtrl.create(me, .Top, {0, 0, cellSize, 0})
        {
            .dockStyle       = .Left
            .spacing         = 0
            .backgroundStyle = .Window
            .style.addStyleSheetColors("wnd_Bk $wnd_CaptionBk")
        }

        let toolButtons = [
            ActionToolMode.Favorites, ActionToolMode.Selection, ActionToolMode.Shape,
            ActionToolMode.Arrow, ActionToolMode.Line, ActionToolMode.Poly,
            ActionToolMode.Text, ActionToolMode.Callout, ActionToolMode.Draw, ActionToolMode.Highlight,
            ActionToolMode.Step, ActionToolMode.Img, ActionToolMode.PixSel]

        for id in toolButtons
        {
            with let b = IconButton.create(me .toolRail!, {}, position: {0, 0, cellSize, cellSize})
            {
                .id = id

                // Air on both sides of the glyph, so the column is separated from the window
                // edge and from the canvas by space rather than by a line.
                .setAllPaddings({cellPadding, 0, cellPadding, 0})
                if id == ActionToolMode.Callout
                {
                    .iconPainter = func(btn, bc, pos, flags) { drawCalloutGlyph(btn, bc, pos, flags) }
                    .setIconSize(glyphSize, glyphSize)
                }

                // A vertical tool rail keeps the leading rule: it reads beside the glyph rather
                // than as part of it, and the reserved lane prevents the content from moving.
                .style.addStyleSheetColors("btnIcon_CheckedBk           $btnIcon_HotBk")
                .style.addStyleSheetColors("btnIcon_CheckedText         $btnIcon_Text")
                .style.addStyleSheetColors("btnIcon_CheckedHotText      $btnIcon_Text")
                .style.addStyleSheetColors("btnIcon_CheckedPressedText  $btnIcon_Text")
                .style.addStyleSheetColors("btnIcon_CheckedIcon         $btnIcon_CheckedMark")
                .style.addStyleSheetColors("btnIcon_CheckedHotBk        $btnIcon_HotBk")
                .style.addStyleSheetColors("btnIcon_CheckedHotIcon      $btnIcon_CheckedHotMark")
                .style.addStyleSheetColors("btnIcon_CheckedPressedIcon  $btnIcon_CheckedMark")

                .updateFlags(.Radio)
                .setTextPosition(.Right)
                .setForm(.Rectangle)
                .setCheckIndicator(.Left)
            }
        }
    }

    // The command row: the two verbs of the application on one side, what the machine
    // knows about the open capture on the other, and nothing in between.
    mtd createCommandRow()
    {
        let metrics    = .themeMetrics()
        let cellSize   = themeActionButtonSize(metrics)
        with let verbs = StackLayoutCtrl.create(me .topBar!, .Left, {0, 0, VerbsWidth, cellSize})
        {
            .dockStyle = .Left
            .spacing   = metrics.iconBar_ButtonsPadding
            .padding   = {2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding, 2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding}
        }

        // Capture is the primary Voltage action. Library has the same push-button shape and
        // footprint, but only takes an informational blue fill while its page is active.
        .captureBtn = PushButton.create(verbs, "", {0, 0, 104, cellSize - 2 * metrics.iconBar_ButtonsPadding}, ActionCapture.DoIt, .Strong)

        with .libraryBtn = PushButton.create(verbs, appStrings().act_Library, {0, 0, 104, cellSize - 2 * metrics.iconBar_ButtonsPadding}, ActionGlobal.ShowLibrary)
        {
            .setIcon(me .icon(.Library))
        }

        with .commandReadouts = StackLayoutCtrl.create(me .topBar!, .Right, {0, 0, ReadoutsWidth, cellSize})
        {
            .dockStyle = .Right
            .spacing   = metrics.iconBar_ButtonsPadding
            .padding   = {2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding, 2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding}
        }

        // Zoom keeps its menu, so it stays a button; size is a pure readout and is not
        // one. Both carry the fixed-width family, so neither jumps as its value changes.
        with .zoomBtn = IconButton.create(.commandReadouts, {}, {0, 0, ReadoutWidth, cellSize - 2 * metrics.iconBar_ButtonsPadding})
        {
            .updateFlags(.CenterContent)
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().res.fontDefaultFs)
            .sigPressed += func|main = me|(btn)
            {
                var menu = MenuCtrl.createPopup(main)
                menu.updateFlags(.HideShortcuts)
                menu.addItem(ActionZoom.Zoom1)
                menu.addItem(ActionZoom.ZoomFit)
                discard menu.doModal(cast(*IconButton) btn, autoDestroy: true)
            }
        }

        with .sizeBtn = IconButton.create(.commandReadouts, {}, {0, 0, ReadoutWidth + 24, cellSize - 2 * metrics.iconBar_ButtonsPadding})
        {
            .updateFlags(.CenterContent | .Flat)
            .style.setFont(me.theme().res.fontDefaultFs)
            .setTextColor(me.themeColors().label_TextLight)
        }
    }

    mtd setTheme()
    {
        .appearanceButton.setAppearanceTheme(.editorOptions.theme)

        // Pixel-selection forms borrow a theme color, so their retained renderings
        // follow the switch.
        if Swag.isSet(.editWnd)
        {
            let capture = .editWnd.getCapture()
            if capture do
                capture.invalidateAllFormCaches()
        }
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

    // Applies the "show tool labels" option. The label never goes under the glyph, which
    // would double the height of every cell to carry a word the tooltip already carries;
    // it widens the rail and sits beside it.
    mtd setToolRailWidth()
    {
        let metrics    = .themeMetrics()
        let showLabels = .editorOptions.showToolBarLabels

        let cellSize    = themeActionButtonSize(metrics)
        let cellPadding = (cellSize - themeActionIconSize(metrics)) * 0.5
        let lane        = metrics.activeRail_Size + metrics.activeRail_Margin
        let width       = showLabels ? RailLabelWidth + lane : cellSize + metrics.activeRail_Size

        for c in .toolRail.children
        {
            if c.type != IconButton do
                continue
            let btn = cast(*IconButton) c
            if showLabels
            {
                btn.updateFlags(remove: .IconOnly)
                btn.setAllPaddings({cellPadding, 0, cellPadding, 0})
            }
            else
            {
                btn.updateFlags(.IconOnly)
                btn.setAllPaddings({0, 0, cellPadding, 0})
            }

            btn.position.width  = width
            btn.position.height = cellSize
        }

        .toolRail.position.width = width

        // The rail width is assigned directly, so arrange its rows explicitly. The main layout
        // then gives the editor its final rectangle and sends its single required resize event.
        .toolRail.sendResizeEvent()
        .applyLayout()
        .toolRail.invalidate()
        .editWnd.invalidate()
    }

    // Creates an icon descriptor for an application glyph at `size` logical pixels.
    mtd icon(idx: CaptureIcons, size = 0.0)->Icon
    {
        let resolvedSize = size ? size : themeActionIconSize(.themeMetrics())
        return .icons.icon(cast(s32) idx, resolvedSize, .theme().res.atlasScale)
    }

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

        with let res = Wnd.create'MainWnd(parent, "capture.mainwnd")
        {
            let resSrf = res.surface!
            resSrf.setView(res)
            .icons.setup(renderer, captureIcons())
            .appIcon.set(renderer.addImage(imgApp))
            .backgroundStyle = .Window
            .mdlFavorite     = &res.mdlFormShape
            .mdlHighlight    = &res.mdlFormShape
            .mdlPixSel       = &res.mdlFormShape
            .monitors        = Env.getMonitors()
        }

        res.appearanceButton                 = AppearanceButton.create(srf, "capture.appearance")
        res.appearanceButton.sigThemeChanged += func|main = res|(button)
        {
            main.editorOptions.theme = button.appearanceTheme
            let capture = main.editWnd.getCapture()
            if capture do
                capture.invalidateAllFormCaches()
            main.saveAppState()
        }
        res.appearanceButton.sigLanguageChanged += func|main = res|(button)
        {
            if button.language.isEmpty() do
                main.editorOptions.language = .System
            elif button.language == "fr" do
                main.editorOptions.language = .French
            else do
                main.editorOptions.language = .English
            main.saveAppState()
        }
        res.appearanceButton.sigAboutRequested += func|main = res|(button)
        {
            discard button
            main.postCommandEvent(ActionAbout.About)
        }

        // One Voltage rail identifies every standard Swag application surface.
        Separator.create(res, .Top, .Accent)

        // One command row, the same height in both modes, instead of the former stack of
        // a command bar and a centered tool ribbon.
        with res.topBar = Wnd.create'Wnd(res, {0, 0, 0, themeActionButtonSize(res.themeMetrics())})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
            .style.addStyleSheetColors("wnd_Bk $wnd_CaptionBk")
        }

        res.createCommandRow()
        res.createToolRail()
        let panelGutter = res.themeMetrics().panel_GutterSize

        // Main edit area. The host supplies the structural gutter behind the rounded View;
        // putting the View directly on the Window ground made the exposed corner pixels read
        // as a second panel underneath it.
        with res.editBar = Wnd.create'Wnd(res)
        {
            .dockStyle       = .Center
            .backgroundStyle = .ToolBar
            .padding.y       = panelGutter
        }

        with res.editWnd = EditWnd.create(res, res.editBar)
        {
            .dockStyle            = .Center
            .backgroundStyle      = .Transparent
            .sigScrollSizeChanged += func|res|(scroll, old, new) { res.updateZoomDisplay(); }
        }

        // Recent bar. The three preview-size buttons that used to stand permanently at its
        // left are gone: a control shown at all times to set a preference costs permanent
        // room and buys one occasional click. The size lives in the View menu.
        with res.recentBar = Wnd.create'Wnd(res, {0, 0, 0, 136})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .ToolBar
            .padding         = {0, panelGutter, panelGutter, 0}
        }

        with res.recentWnd = RecentWnd.create(res.recentBar, res)
        {
            .dockStyle = .Center
        }

        // Right bar: one column, one heading naming the tool it edits. The two pane titles
        // it replaces said what the reader could already see; this one does not.
        with res.rightBar = Wnd.create'Wnd(res, {0, 0, RightPanelWidth + 2 * panelGutter, 0})
        {
            .dockStyle       = .Right
            .backgroundStyle = .ToolBar
            .padding         = {panelGutter, panelGutter, panelGutter, 0}
        }

        with let rightPanel = Wnd.create'Wnd(res.rightBar, {0, 0, RightPanelWidth, 0})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        with res.quickStyleBar = SplitterCtrl.create(rightPanel, {0, 0, RightPanelWidth, 600}, vertical: true)
        {
            .dockStyle       = .Center
            .backgroundStyle = .ToolBar
        }

        with let quickPane = Wnd.create'Wnd(res.quickStyleBar)
        {
            .backgroundStyle = .Panel
        }

        // The heading starts on the same margin as the cells and the rows under it: a title
        // centred over a left-aligned column is a second alignment on one narrow panel.
        with res.toolTitle = Label.create(quickPane, "", {0, 0, 0, ToolTitleHeight})
        {
            .dockStyle = .Top
            .style.setFont(res.theme().res.fontDefaultFs)
            .setTextAlignment(.Left, .Center)
            .setTextPadding({12, 8, 12, 0})
            .setTextColor(res.themeColors().label_TextLight)
        }

        with res.quickWnd = QuickWnd.create(quickPane, res)
        {
            .dockStyle = .Center
        }

        with let propPane = Wnd.create'Wnd(res.quickStyleBar)
        {
            .backgroundStyle = .Panel
        }

        with res.propWnd = PropWnd.create(propPane, res)
        {
            .dockStyle = .Center
        }

        with let quickItem = res.quickStyleBar.addPane(quickPane)
        {
            .preserveSize = true
        }

        discard res.quickStyleBar.addPane(propPane)
        res.quickStyleBar.setPaneSize(0, 168 + ToolTitleHeight)

        // Initialize everything
        with res
        {
            // Theme and language before anything is built from a string: they used to be
            // applied only while reading the persisted state, so a first run — which has no
            // state to read — stayed on the reference English wording whatever the locale.
            .setTheme()
            .setLanguage()
            .registerActions()
            .registerShortcuts()
            .updateZoomDisplay()
            .updateSizeDisplay()
            .setBottomSize(.Medium, animated: false)
            .setToolRailWidth()
            .updateState()
            .libWnd = LibraryWnd.create(res)
            .libWnd.hide()
        }

        g_Main = res
        return res
    }
}
