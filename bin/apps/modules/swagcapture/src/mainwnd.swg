// The main window once [[MainWnd.create]] has run. Headless fixtures that build a panel on its
// own leave it null.
var g_Main: *MainWnd?

const ClipboardFormat        = "Swag.Capture"
const CaptureFileMetadataTag = "Swag.Capture.File"
const IconsSvg               = #include("../datas/icons.svg")
const AppIcon                = #include("../datas/appicon.png")

// The editor tool, which decides what a drag on the capture creates.
enum EditMode { Shape, Arrow, Line, Polygon, Text, Favorites, Draw, Highlight, Selection, Step, Image, PixSel, Callout }

// What the mini-bar beside the selection carries: nothing without a selection, the colour of one
// object, the face of a text, the counter of a step, or the alignment of several objects.
enum MiniBarKind { None, Single, Text, Step, Multi }

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

// The application window: the capture on the ground with the tool dock, the inspector, the
// mini-bar and the hint line floating over it, or the library; the lens over both.
struct MainWnd
{
    using wnd: Wnd

    late
    {
        editArea, recentBar: *Wnd
        editWnd:             *EditWnd
        dock:                *ToolDock
        inspector:           *Inspector
        miniBar:             *MiniBar
        hintLine:            *HintLine
        toast:               *Toast
        lens:                *Lens.View
        quickWnd:            *QuickWnd
        propWnd:             *PropWnd
        libWnd:              *LibraryWnd
        recentWnd:           *RecentWnd
        appearanceButton:    *AppearanceButton
    }

    embInfoFreeze: *InfoBar?

    // The kind of selection the mini-bar was last built for, so it is rebuilt only when that changes.
    miniBarKind: MiniBarKind = .None
    miniBarForm: *BaseForm?     // The form the mini-bar was filled for, whose face, size and style it shows.
    icons:       IconSet
    appIcon:     ImageList
    monitors:    Array'Env.Monitor

    // State
    editMode:      EditMode   = .Shape
    bottomSize:    BottomSize = .Medium
    pixSelFillCol: Color      = Argb.White
    inPlaceEdit, snap, freezeSel, libraryMode: bool
    showRecent, inspectorFolded: bool

    // The files saved during the session, which the "Show" of a toast opens the folder of.
    savedPaths: Array'String

    // What the action of the toast on screen runs.
    toastAction:           (func||())?
    recentColors:          Array'Color
    firstShow:             bool = true
    fileDlgState, fileDlgStateInPlace: FileDlgState
    libraryFolderDlgState: FileDlgState
    exportFolderDlgState:  FileDlgState
    libraryFolder:         String
    captureOptions:        CaptureOptions
    editorOptions:         EditorOptions

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
                with let surface = unwrap .surface
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

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .miniBar != null do
            .placeMiniBar()
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
                try .serialize("MainWnd.showRecent", &me.showRecent)
                try .serialize("MainWnd.recentColors", &me.recentColors)
                try .serialize("MainWnd.inspectorFolded", &me.inspectorFolded)
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
            .setBottomSize(.bottomSize, animated: false)
            .showRecentBar(.showRecent)
            .inspector.setFolded(.inspectorFolded)
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
        sf.setPosition(Math.Rectangle{pt.x, pt.y, menu.position.width * sf.dpiScale, menu.position.height * sf.dpiScale})
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
        if cast(u32, .editorOptions.theme) > cast(u32, AppearanceTheme.System) do
            .editorOptions.theme = .Dark
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
        catch capture.save() do
            MessageDlg.error(unwrap .surface, Format.toString(appStrings().msg_FailedSaveCapture, capture.file))
    }

    // Waits for the background save targeting `file` (any when null) and reports its
    // failure, which the timer that scheduled it can no longer do.
    mtd flushCaptureSave(file: string? = null)
    {
        let failed = g_CaptureSaves.flush(file)
        if not failed.isEmpty() do
            MessageDlg.error(unwrap .surface, Format.toString(appStrings().msg_FailedSaveCapture, failed))
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
            }
            {
                MessageDlg.error(unwrap .surface, appStrings().msg_FailedRename, Swag.err)
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
        }
        {
            MessageDlg.error(unwrap .surface, appStrings().msg_FailedCopyImage, Swag.err)
        }
    }

    // Opens the image file `arg`: the capture it was exported from when Swag Capture wrote it,
    // otherwise a new capture linked to the file.
    mtd loadExternalImage(arg: String)
    {
        let imgToLoad = catch Image.load(arg)
        {
            MessageDlg.error(unwrap .surface, Format.toString(appStrings().msg_FailedLoadFile, arg), Swag.err)
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
                it.freeze = true
        }
    }

    mtd updateState()
    {
        // The tool in use stands in the dock, in the cell of its group when it has one.
        if .dock != null do
            discard .dock.selectTool(toolCommand(.editMode))
        .updateCommandState()
        .updateInspectorTitle()
        .fillHintLine()
        if .propWnd != null do
            .propWnd.selectionHasChanged()
        if .quickWnd != null do
            .quickWnd.updateQuickStyles()
        .updateMiniBar()
    }

    mtd captureHasChanged()
    {
        .updateReading()
        if .recentWnd != null
        {
            .updateCommandState()
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

    // Writes the size and the zoom of the capture at the head of the hint line. Both are machine
    // data, set in the fixed-width family by the line itself.
    mtd updateReading()
    {
        if .hintLine == null do
            return

        let capture = .editWnd.getCapture()
        if not capture
        {
            .hintLine.setReading(null)
            return
        }

        // The percent sign is appended rather than formatted: '%' is the placeholder itself.
        var reading = Format.toString("% × % · %", capture.width, capture.height, cast(s32, Math.round(.editWnd.editView.zoom * 100)))
        reading += " %"
        .hintLine.setReading(reading)
    }

    // Returns the name of a tool, as the inspector heads the properties it edits.
    // Reports whether `title` fits the head of the inspector before its actions.
    mtd titleFits(title: string)->bool
    {
        let metrics = .themeMetrics()
        let theme   = .theme()
        let words   = Painter.measureString(title, theme.createDefaultFont(metrics.inspector_TitleFontSize, .Bold)).width
        let small   = theme.createDefaultFont(metrics.defaultFontSize - 1)
        let actions = Painter.measureString(Format.toString("% · %", appStrings().act_Duplicate, appStrings().act_Delete), small).width
        let room    = metrics.inspector_Width - 2 * metrics.inspector_Padding - actions - 2 * metrics.btnIcon_SpacingTextH - metrics.iconText_Margin
        return words <= room
    }

    // Returns the words counting one kind of object, from a table of "singular|plural" words.
    func countWords(table: string, count: u64)->String
    {
        let parts = Tokenize.split(table, '|'u8, removeEmpty: false)
        let words = (count == 1 or parts.count < 2) ? parts[0] : parts[1]
        return Format.toString(words, count)
    }

    // Returns the words counting each kind of the selected objects, in the order they first come,
    // such as "2 rectangles · 1 text".
    func describeKinds(capture: *Capture)->String
    {
        var tables: Array'string
        var counts: Array'u64
        for index in capture.selection
        {
            let table = kindCountTable(capture.forms[index])
            var found = false
            for t, i in tables where t == table
            {
                counts[i] += 1
                found     = true
            }

            if not found
            {
                tables.add(table)
                counts.add(1)
            }
        }

        var result: String
        for t, i in tables
        {
            if i do
                result += " · "
            result += countWords(t, counts[i])
        }

        return result
    }

    // Returns the "singular|plural" words counting objects of the kind of `form`.
    func kindCountTable(form: IForm)->string
    {
        let texts = appStrings()
        let base: *BaseForm = form
        if base.subKind == .Highlight do
            return texts.count_Highlight
        if base.subKind == .PixSel do
            return texts.count_PixSel

        switch form
        {
        case FormShape as shape: return shape.kind == .Ellipse ? texts.count_Ellipse : texts.count_Rectangle
        case FormArrow:          return texts.count_Arrow
        case FormLine:           return texts.count_Line
        case FormPolygon:        return texts.count_Polygon
        case FormText:           return texts.count_Text
        case FormCallout:        return texts.count_Callout
        case FormDraw:           return texts.count_Draw
        case FormStep:           return texts.count_Step
        case FormImage:          return texts.count_Image
        }

        return texts.count_Object
    }

    func editModeName(mode: EditMode)->string
    {
        switch #complete mode
        {
        case .Shape:     return appStrings().act_Shape
        case .Arrow:     return appStrings().act_Arrow
        case .Line:      return appStrings().act_Line
        case .Polygon:   return appStrings().act_Polygon
        case .Text:      return appStrings().act_Text
        case .Callout:   return appStrings().act_Callout
        case .Draw:      return appStrings().act_Draw
        case .Highlight: return appStrings().act_Highlight
        case .Step:      return appStrings().act_Step
        case .Image:     return appStrings().ui_MenuImage
        case .PixSel:    return appStrings().act_PixSel
        case .Favorites: return appStrings().act_Favorites
        case .Selection: return appStrings().act_Select
        }
    }

    // Confirms what the hand just did in a toast at the foot of the window: `message`, a name or
    // a path in `detail`, and an `action` word that runs `onAction` when clicked.
    mtd confirm(message: string, detail: string = "", action: string = "", onAction: (func||())? = null)
    {
        if .toast == null do
            return
        .toastAction = onAction
        .toast.show(message, detail, .Done, action)
    }

    // Returns the glyph of a tool, as the dock and the layers of the inspector show it.
    func editModeIcon(mode: EditMode)->CaptureIcons
    {
        switch #complete mode
        {
        case .Shape:     return .Shape
        case .Arrow:     return .Arrow
        case .Line:      return .Line
        case .Polygon:   return .Polygon
        case .Text:      return .Text
        case .Callout:   return .Text
        case .Draw:      return .Draw
        case .Highlight: return .Highlight
        case .Step:      return .Step
        case .Image:     return .Image
        case .PixSel:    return .PixSel
        case .Favorites: return .Favorites
        case .Selection: return .Select
        }
    }

    // Names what the inspector edits: the selected objects and their count, or the tool whose
    // next objects take these settings; and offers Duplicate and Delete for a selection.
    mtd updateInspectorTitle()
    {
        if .inspector == null do
            return

        .inspector.clear()
        let capture = .getCapture()
        let count   = capture ? capture.selection.count : 0
        if count == 0
        {
            .inspector.setTitle(editModeName(.getEditMode()), appStrings().ui_NextObjects)
            return
        }

        if count == 1
        {
            .inspector.setTitle(editModeName(formToEditMode(capture!.forms[capture.selection.back()])), appStrings().ui_OneObject)
        }
        else
        {
            // Several objects are named by what they are, "2 rectangles · 1 text", when that fits
            // before the actions of the head; otherwise by how many they are.
            let kinds = describeKinds(unwrap capture)
            if .titleFits(kinds) do
                .inspector.setTitle(kinds)
            else do
                .inspector.setTitle(Format.toString(appStrings().ui_Objects, count))
        }

        // The actions are words: the commands they post carry glyphs for the lens.
        .inspector.addAction(appStrings().act_Duplicate).sigPressed += func|main = me|(_) { main.postCommandEvent(ActionCopyPaste.Duplicate) }
        .inspector.addAction(appStrings().act_Delete).sigPressed    += func|main = me|(_) { main.postCommandEvent(ActionSelection.DeleteSelection) }
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
        .registerKeyShortcut(.Control, .A, ActionSelection.SelectAll)
        .registerKeyShortcut(.None, .Escape, ActionSelection.DeSelectAll)
        .registerKeyShortcut(.Control, .D, ActionCopyPaste.Duplicate)
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

        // ] and [ bring an object forward or back a step, with Ctrl to the front or the back.
        .registerKeyShortcut(.None, .Oem6, ActionAlign.MoveForward)
        .registerKeyShortcut(.None, .Oem4, ActionAlign.MoveBackward)
        .registerKeyShortcut(.Control, .Oem6, ActionAlign.SendToFront)
        .registerKeyShortcut(.Control, .Oem4, ActionAlign.SendToBack)
        .registerKeyShortcut(.None, .Home, ActionAlign.SendToFront)
        .registerKeyShortcut(.None, .End, ActionAlign.SendToBack)
        .registerKeyShortcut(.None, .PageUp, ActionAlign.MoveForward)
        .registerKeyShortcut(.None, .PageDown, ActionAlign.MoveBackward)

        // The arrows nudge the selection a pixel, ten with Shift.
        .registerKeyShortcut(.None, .Left, ActionMoveSel.Left1)
        .registerKeyShortcut(.None, .Up, ActionMoveSel.Top1)
        .registerKeyShortcut(.None, .Right, ActionMoveSel.Right1)
        .registerKeyShortcut(.None, .Down, ActionMoveSel.Bottom1)
        .registerKeyShortcut(.Shift, .Left, ActionMoveSel.Left)
        .registerKeyShortcut(.Shift, .Up, ActionMoveSel.Top)
        .registerKeyShortcut(.Shift, .Right, ActionMoveSel.Right)
        .registerKeyShortcut(.Shift, .Down, ActionMoveSel.Bottom)
        .registerKeyShortcut(.Control, .Add, ActionZoom.ZoomIn)
        .registerKeyShortcut(.Control, .Subtract, ActionZoom.ZoomOut)
        .registerKeyShortcut(.Control, .NumPad0, ActionZoom.Zoom1)

        // Each tool answers a letter, the one the dock and the lens name: inside a field the
        // letter is typed, so a field keeps it.
        .registerKeyShortcut(.None, .V, ActionToolMode.Selection)
        .registerKeyShortcut(.None, .R, ActionToolMode.Shape)
        .registerKeyShortcut(.None, .P, ActionToolMode.Poly)
        .registerKeyShortcut(.None, .A, ActionToolMode.Arrow)
        .registerKeyShortcut(.None, .L, ActionToolMode.Line)
        .registerKeyShortcut(.None, .T, ActionToolMode.Text)
        .registerKeyShortcut(.None, .C, ActionToolMode.Callout)
        .registerKeyShortcut(.None, .D, ActionToolMode.Draw)
        .registerKeyShortcut(.None, .H, ActionToolMode.Highlight)
        .registerKeyShortcut(.None, .N, ActionToolMode.Step)
        .registerKeyShortcut(.None, .M, ActionToolMode.Img)
        .registerKeyShortcut(.None, .X, ActionToolMode.PixSel)
        .registerKeyShortcut(.None, .F, ActionToolMode.Favorites)

        // The one door is a chord so Space remains available to the work and to text fields.
        .registerKeyShortcut(.Control, .Space, ActionView.Lens)
        .registerKeyShortcut(.None, .I, ActionView.Inspector)

        // Every shortcut another application already owns is named in one information bar.
        var taken: Array'String

        #[Swag.Mixin]
        mtd registerHotKey(modifiers: Input.KeyModifiers, key: Input.Key, wndId: WndId)
        {
            catch .app().registerHotKey(modifiers, key, wndId, me) do
                taken.add(Input.formatKeyShortcut(modifiers, key))
        }

        .registerHotKey(.None, .PrintScreen, ActionCapture.Area)
        .registerHotKey(.CtrlShift, .PrintScreen, ActionCapture.LastArea)
        .registerHotKey(.Control, .PrintScreen, ActionCapture.FullScreen)
        .registerHotKey(.Alt, .PrintScreen, ActionCapture.ActiveWnd)

        if taken.count == 1
        {
            var msg = Format.toString(appStrings().msg_ShortcutTaken, taken[0])
            msg += appStrings().msg_ShortcutTakenWhy
            discard InfoBar.create(.editWnd, msg, .Critical)
        }
        elif taken.count > 1
        {
            var names: String
            for name, index in taken
            {
                if index != 0 do
                    names += ", "
                names += Format.toString("'%'", name)
            }

            var msg = Format.toString(appStrings().msg_ShortcutsTaken, names)
            msg += appStrings().msg_ShortcutsTakenWhy
            discard InfoBar.create(.editWnd, msg, .Critical)
        }
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

    // Creates the glyph of a tool, at the size the dock draws it.
    mtd toolIcon(idx: CaptureIcons)->Icon => .icon(idx, .themeMetrics().toolDock_Glyph)

    // Creates an icon descriptor for an application glyph at `size` logical pixels.
    mtd icon(idx: CaptureIcons, size = 0.0)->Icon
    {
        let resolvedSize = size ? size : themeActionIconSize(.themeMetrics())
        return .icons.icon(cast(s32, idx), resolvedSize, .theme().res.atlasScale)
    }

    // Builds the main window: the work area with its dock, inspector, mini-bar and hint line,
    // the recent strip it shows on demand, the library hidden until it is asked for, and the
    // lens that reaches every command.
    func create(parent: *Wnd)->*MainWnd
    {
        let srf = unwrap parent.surface
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
        result.createRecentBar()
        result.createEditArea()
        result.createDock()
        result.createInspector()
        result.createMiniBar()
        result.createHintLine()
        result.toast = Toast.create(result)
        result.toast.sigAction += func|main = result|(_)
        {
            if main.toastAction do
                main.toastAction()
        }

        with result
        {
            // Theme and language come before anything is built from a string. A first run has
            // no persisted state to read them from, and would otherwise stay on the reference
            // English wording whatever the locale.
            .setTheme()
            .setLanguage()
            .registerActions()
            .registerShortcuts()
            .setBottomSize(.Medium, animated: false)
            .libWnd = LibraryWnd.create(result)
            .libWnd.hide()
            .createLens()
            .updateReading()
            .updateState()
        }

        // The ground around the picture moves the window, as the strip does.
        result.surface!.wnd.groundHitTest = func|result|(pos) => result.editWnd.editView.isWindowGround(pos)

        g_Main = result
        return result
    }
}
