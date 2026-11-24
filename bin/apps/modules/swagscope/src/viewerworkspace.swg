#global internal

using Core, Gui, Pixel

enum SceneLayout
{
    Single
    SideBySide
    Stacked
    Grid2
    Grid3
    Grid4
    Auto
}

struct SceneView
{
    path:      String
    document:  *ViewerWindow?
    reading:   ViewerReadingState
    readState: bool
    playMode:  Viewer.PlayMode
    offset:    f64
    behind:    bool
    cellPlusOne: u64  // Zero follows document order. A file placed in a hole keeps its chosen cell.
}

struct ViewerScene
{
    views:              Array'SceneView
    layout:             SceneLayout = .Auto
    active:             u64
    recent:             u64
    split:              f32         = 0.5
    maximized:          bool
    compared:           bool
    linked:             bool
    playbackWasRunning: bool
    links:              SceneLinks
    comparisonState:    SceneComparisonState
    preview:            Texture
}

impl ViewerScene
{
    mtd const cellOf(index: u64)->u64 => .views[index].cellPlusOne ? .views[index].cellPlusOne - 1 : index

    mtd const viewInCell(cell: u64)->u64
    {
        for _, index in .views where .cellOf(index) == cell do
            return index
        return Swag.U64.Max
    }

    mtd const cellCount()->u64
    {
        let size = .dimensions()
        return cast(u64, size.x * size.y)
    }

    mtd packCells()
    {
        for &view in .views do
            view.cellPlusOne = 0
    }

    mtd removeView(index: u64)
    {
        var sparse = false
        for _, i in .views where .cellOf(i) != i
        {
            sparse = true
            break
        }
        if sparse
        {
            for &view, i in .views do
                view.cellPlusOne = .cellOf(i) + 1
        }
        .views.removeAtOrdered(index)
        if sparse and .views.count > 1
        {
            let dims = .dimensions(useMaximized: false)
            let cells = cast(u64, dims.x * dims.y)
            for _, i in .views where .cellOf(i) >= cells
            {
                .packCells()
                return
            }
        }
        else do
            .packCells()
    }

    mtd const visibleLayout()->SceneLayout => .maximized ? .Single : .layout

    mtd const dimensions(useMaximized = true)->Math.Point
    {
        if .views.count <= 1 or useMaximized and (.layout == .Single or .maximized) do
            return {1, 1}
        switch .layout
        {
        case .SideBySide where .views.count == 2: return {2, 1}
        case .Stacked where .views.count == 2:    return {1, 2}
        case .Grid4:                              return {4, 4}
        case .Grid3 where .views.count <= 9:      return {3, 3}
        case .Grid2 where .views.count <= 4:      return {2, 2}
        default:                                  break
        }

        if .views.count <= 2 do
            return {2, 1}
        if .views.count <= 4 do
            return {2, 2}
        if .views.count <= 9 do
            return {3, 3}
        return {4, 4}
    }

    mtd const supportsLayout(layout: SceneLayout)->bool
    {
        switch #complete layout
        {
        case .SideBySide, .Stacked:  return .views.count == 2
        case .Grid2:                 return .views.count <= 4
        case .Grid3:                 return .views.count <= 9
        case .Single, .Grid4, .Auto: return true
        }
    }

    mtd swapViews(first, second: u64)
    {
        var view = #move .views[first]
        .views[first]  = #move .views[second]
        .views[second] = #move view
        swap(&.views[first].cellPlusOne, &.views[second].cellPlusOne)
        .links.leader  = remapSwappedView(.links.leader, first, second)
        .links.solo    = remapSwappedView(.links.solo, first, second)
    }
}

private func remapSwappedView(index, first, second: u64)->u64 => index == first ? second : (index == second ? first : index)

private func remapClosedView(index, removed: u64)->u64
{
    if index == Swag.U64.Max or index == removed do
        return Swag.U64.Max
    return index > removed ? index - 1 : index
}

struct ViewerWorkspace
{
    using wnd: Wnd

    late primary:         *ViewerWindow
    late tabs:            *SceneTabs
    late divider:         *SceneDivider
    late mediaLinks:      *CaptionButton
    late mediaTransport:  *CaptionButton
    late mediaPlayPause:  *CaptionButton

    scenes:           ArrayPtr'ViewerScene
    active:           u64
    activation:       u64
    paintedScene:     u64
    retiring:         Array'(*ViewerWindow)
    retireTimer:      *Timer?
    restored:         Array'SavedScene
    restoredTab:      u64
    startupFiles:     Array'String
    startupLayout:    SceneLayout
    switchOrder:      Array'u64
    switchCursor:     u64
    switcher:         *FloatingPanel?
    switchBackdrop:   *Wnd?
    focusOnGrid:      bool          // The title strip has released the cell while the scene keeps its playback leader.
    hoveredDocument:  *ViewerWindow?
    pointerKnown:     bool
    pointerPosition:  Math.Point
    maxHint:          *HintLine?
    maxHintTimer:     *Timer?
    comparison:       *SceneComparison?
    comparisonScene:  *ViewerScene?
    comparisonSheet:  *ComparisonSheet?
    mediaTimer:       *Timer?
    mediaPlayKeyDown: bool
    alignSound:       SceneSoundAlignment
    dropView:         u64 = Swag.U64.Max
    vacancy:          *ViewerWindow?
    vacantCell:       u64
    readingLinksBusy: bool
}

impl ViewerWorkspace
{
    const MaxViews        = 16
    const MaxScenes       = 32
    const ViewTitleHeight = 26.0

    func create(parent: *Wnd, index: #move ViewerPluginRegistry)->*ViewerWorkspace
    {
        let result = Wnd.create'ViewerWorkspace(parent, "scope.workspace")
        result.focusPolicy = .Click
        result.backgroundStyle = .Application
        result.wndFlags.add(.AfterChildrenPaint)
        result.surface!.setView(result)
        result.surface.wnd.sigCaptionPressed += func(frame)
        {
            if frame.view is ViewerWorkspace as workspace do
                workspace.releaseCellFocus()
        }
        result.primary             = ViewerWindow.create(result, #move index, result)
        result.primary.focusPolicy = .Click
        result.tabs                = SceneTabs.create(result)
        result.divider             = SceneDivider.create(result)
        result.createMediaControls()
        result.hookOnChildEvent    = func|workspace = result|(_, evt)
        {
            switch evt
            {
            case KeyEvent as key:
                return key.target != null and workspace.routeSceneKey(key, key.target)

            case DragDropEvent as drag where drag.data.hasFiles() and workspace.documentCount() > 1:
                // A cell owns its file drops. An explorer still ignores its own drag.
                let explorer = workspace.activeDocument().explorer
                if not explorer or not explorer.draggingFile or not explorer.isOwnerOf(drag.target) do
                    return workspace.dropFiles(drag)

            case MouseEvent as pointer where pointer.kind == .Move or pointer.kind == .Enter or pointer.kind == .Leave:
                workspace.trackViewHover(pointer)

            case MouseEvent as pointer where pointer.kind == .Pressed or pointer.kind == .DoubleClick:
                if pointer.target do
                    return workspace.activateFromPointer(pointer.target, pointer)
            }

            return false
        }

        result.layoutScene()
        return result
    }

    mtd scene()->*ViewerScene?
    {
        if .active >= .scenes.count do
            return null
        return .scenes[.active]
    }

    mtd activeDocument()->*ViewerWindow
    {
        if .vacancy do
            return .vacancy
        let scene = .scene()
        if not scene or scene.active >= scene.views.count do
            return .primary
        return scene.views[scene.active].document orelse .primary
    }

    mtd sceneName(scene: const *ViewerScene)->String
    {
        if scene.views.isEmpty() do
            return ProductName
        let first: string = Path.fileName(scene.views[0].path) orelse scene.views[0].path
        if scene.views.count == 1 do
            return first
        if scene.views.count == 2
        {
            let second: string = Path.fileName(scene.views[1].path) orelse scene.views[1].path
            return Format.toString("% ↔ %", first, second)
        }

        for view in scene.views where .scenePlaybackKind(view) != .Film do
            return Format.toString(appStrings().scene_Files, scene.views.count)
        return Format.toString(appStrings().scene_Videos, scene.views.count)
    }

    mtd documentCount()->u64 => .scene()?.views.count orelse 0

    mtd isTiled()->bool
    {
        let scene = .scene()
        return scene and scene.views.count > 1 and not scene.maximized and scene.layout != .Single
    }

    mtd usesCellCaptions()->bool => .documentCount() > 1 and not .comparisonVisible()

    func attachDocument(workspace: *ViewerWorkspace, view: *SceneView, remember: bool)
    {
        let document = ViewerWindow.create(workspace, createViewerPluginRegistry(), workspace)
        view.document        = document
        document.focusPolicy = .Click
        document.playMode    = view.playMode
        document.onlineMovies = workspace.primary.onlineMovies
        document.onlineMusic  = workspace.primary.onlineMusic
        document.applyFullScreenPresentation(workspace.primary.fullScreen)
        if view.readState
        {
            document.readingState = view.reading
            document.readingState.useSavedViewer = true
        }

        document.queueFile(view.path, remember, preserveReading: view.readState)
    }

    mtd adoptPrimary(path: string)
    {
        if not .scenes.isEmpty() do
            return
        let scene = .scenes.addNew()
        scene.views.add({path: String.from(path), document: .primary})
        scene.layout = .Single
        .activation  += 1
        scene.recent = .activation
        .active      = 0
    }

    mtd openDocument(path: string, remember = true)
    {
        var paths: Array'String
        paths.add(path)
        .openScene(paths.toSlice(), .Single, remember: remember)
    }

    mtd openScene(paths: const [..] String, layout: SceneLayout, compare = false, remember = true)
    {
        if not paths.count do
            return
        if paths.count > MaxViews or .scenes.count >= MaxScenes
        {
            Toast.create(me).show(paths.count > MaxViews ? appStrings().scene_ViewLimit : appStrings().scene_TabLimit, tone: .Failure)
            return
        }

        .suspendScene()
        var next: ViewerScene
        next.maximized = layout == .Single and paths.count > 1
        next.layout   = next.maximized ? .Auto : layout
        next.compared = compare and paths.count == 2
        for path in paths do
            next.views.add({path: path[]})
        next.linked = next.compared or paths.count > 1 and layout != .SideBySide and .allMedia(&next)
        .scenes.addNew()[] = #move next
        .active = .scenes.count - 1

        if .active == 0 and
           .primary.currentFile.isEmpty() and
           .primary.pendingFile.isEmpty() and
           not .primary.isExploring()
        {
            let view = &.scenes[0]!.views[0]
            view.document = .primary
            .primary.queueFile(view.path, remember)
        }

        .resumeScene(remember)
    }

    mtd replaceDocument(index: u64, path: string)
    {
        let scene = .scene()
        if not scene or index >= scene.views.count do
            return
        let view = &scene.views[index]
        let document = view.document
        if not document do
            return

        view.path      = path
        view.reading   = {}
        view.readState = false
        view.offset    = 0
        view.behind    = false
        if scene.links.leader == index do
            scene.links.leader = Swag.U64.Max
        if scene.links.solo == index do
            scene.links.solo = Swag.U64.Max
        document.queueFile(path)
        if scene.active == index and not .focusOnGrid do
            .showScene()
        else do
            .selectView(index)
    }

    mtd openBeside(path: string)
    {
        let scene = .scene()
        if not scene or scene.views.count >= MaxViews do
            return
        .dismissVacancy()
        scene.packCells()
        let index = scene.active + 1
        if scene.links.leader >= index and scene.links.leader < scene.views.count do
            scene.links.leader += 1
        if scene.links.solo >= index and scene.links.solo < scene.views.count do
            scene.links.solo += 1
        scene.views.insertAt(index, SceneView{path: String.from(path)})
        scene.active    = index
        scene.layout    = scene.views.count == 2 ? .SideBySide : .Auto
        scene.maximized = false
        scene.compared  = false
        scene.linked    = false
        ViewerWorkspace.attachDocument(me, &scene.views[index], remember: true)
        .showScene()
    }

    mtd updateDocumentPath(document: *ViewerWindow, path: string)
    {
        let scene = .scene()
        if not scene do
            return
        for &view in scene.views where view.document == document and view.path != path
        {
            view.path      = path
            view.readState = false
            .tabs.layoutTabs()
            return
        }
    }

    mtd suspendScene(capturePreview = true)
    {
        .focusOnGrid = false
        .dismissVacancy()
        .clearDropHighlight()
        .hoveredDocument = null
        .mediaPlayKeyDown = false
        .showMaximizedHint(false)
        .divider.stopDrag()
        .closeSwitcher(choose: false)
        let scene = .scene()
        if not scene do
            return
        if capturePreview do
            .captureScenePreview()
        .storeComparisonState()
        .comparisonScene = null
        .closeComparisonSheet()
        for &view in scene.views
        {
            let document = view.document
            if not document do
                continue
            .captureView(view)
            .primary.privacy.track(view.path, document.privacy.policy(view.path))
            view.document = null
            .retireDocument(document)
        }
    }

    mtd captureView(view: *SceneView)
    {
        let document = view.document
        if not document do
            return
        view.playMode = document.playMode
        if document.currentFile != view.path or
           document.activeChoiceIndex >= document.instances.count do
            return
        let session = &document.instances[document.activeChoiceIndex]
        if not session.view or document.readingState.restoring do
            return
        view.reading.capture(session, document.choices[document.activeChoiceIndex].key, document.searchBox.text())
        view.reading.captureSearchSettings(document)
        view.readState = true
    }

    mtd resumeScene(remember: bool)
    {
        let scene = .scene()
        if scene
        {
            .activation  += 1
            scene.recent = .activation
            for &view in scene.views where not view.document do
                ViewerWorkspace.attachDocument(me, view, remember)
        }

        .showScene()
    }

    mtd selectScene(index: u64, capturePreview = true)
    {
        if index >= .scenes.count or index == .active do
            return
        .suspendScene(capturePreview)
        .active = index
        .resumeScene(false)
        catch .primary.saveState()
    }

    mtd releaseCellFocus()
    {
        if not .isTiled() or .focusOnGrid do
            return
        let previous = .activeDocument()
        previous.hideSearch()
        previous.closeInformation()
        .dismissVacancy()
        .focusOnGrid = true
        .showScene()
    }

    mtd selectView(index: u64)
    {
        let scene = .scene()
        if not scene or index >= scene.views.count or (index == scene.active and not .vacancy and not .focusOnGrid) do
            return
        let previous = .activeDocument()
        if previous != scene.views[index].document
        {
            previous.explorer?.address.hide()
            previous.hideSearch()
            previous.closeInformation()
            previous.concealViewerBar()
        }
        .dismissVacancy()
        .focusOnGrid = false
        scene.active = index
        .showScene()
    }

    // A selected hole borrows a window for its ordinary open commands. It becomes a scene
    // document only once a file or folder is chosen, so traversal never changes the session.
    mtd focusVacancy(cell: u64)
    {
        let scene = .scene()
        if not scene or not .isTiled() or cell >= scene.cellCount() or scene.viewInCell(cell) != Swag.U64.Max do
            return
        .focusOnGrid = false
        if not .vacancy
        {
            let previous = .activeDocument()
            previous.explorer?.address.hide()
            previous.hideSearch()
            previous.closeInformation()
            previous.concealViewerBar()
            .vacancy = ViewerWindow.create(me, createViewerPluginRegistry(), me)
            .vacancy.focusPolicy = .Click
            .vacancy.onlineMovies = .primary.onlineMovies
            .vacancy.onlineMusic = .primary.onlineMusic
            .vacancy.applyFullScreenPresentation(.primary.fullScreen)
            .vacancy.home.hide()
            .vacancy.hintLine.clearHints()
            .vacancy.hintLine.addHint(.vacancy.keyShortcutName(ViewerCommands.Open), appStrings().hint_Open)
            .vacancy.hintLine.addHint(.vacancy.keyShortcutName(ViewerCommands.Explore), appStrings().cmd_Explore)
            .vacancy.hintLine.show()
        }
        .vacantCell = cell
        .showScene()
    }

    mtd dismissVacancy()
    {
        let document = .vacancy
        if not document do
            return
        .vacancy = null
        .retireDocument(document)
    }

    mtd fillVacancy(document: *ViewerWindow, path: string)
    {
        if .vacancy != document do
            return
        let scene = unwrap .scene()
        scene.views.add({path: String.from(path), document: document, cellPlusOne: .vacantCell + 1})
        scene.active = scene.views.count - 1
        document.hintLine.hide()
        .vacancy = null
        .layoutScene()
    }

    mtd closeDocument(document: *ViewerWindow)
    {
        if document == .vacancy
        {
            .closeView()
            return
        }
        let scene = .scene()
        if not scene do
            return
        for view, index in scene.views where view.document == document
        {
            .closeView(index)
            return
        }
    }

    mtd closeView(index = Swag.U64.Max)
    {
        let scene = .scene()
        if not scene
        {
            if index == Swag.U64.Max do
                .primary.closeFile()
            return
        }

        if .vacancy
        {
            .dismissVacancy()
            if index == Swag.U64.Max
            {
                .showScene()
                return
            }
        }
        let closing = index == Swag.U64.Max ? scene.active : index
        if closing >= scene.views.count do
            return
        if scene.views.count == 1
        {
            .closeScene(.active)
            return
        }

        .clearDropHighlight()
        .retireDocument(unwrap scene.views[closing].document)
        scene.removeView(closing)
        scene.links.leader = remapClosedView(scene.links.leader, closing)
        scene.links.solo   = remapClosedView(scene.links.solo, closing)
        scene.active       = scene.active == closing ? Math.min(closing, scene.views.count - 1) : remapClosedView(scene.active, closing)
        scene.compared     = false
        scene.maximized    = false
        if scene.views.count == 1
        {
            scene.layout = .Single
            scene.linked = false
        }
        .showScene()
        .showMaximizedHint(false)
        catch .primary.saveState()
    }

    mtd closeScene(index: u64)
    {
        if index >= .scenes.count do
            return
        .closeSwitcher(choose: false)
        let selected = index == .active
        if selected do
            .suspendScene(capturePreview: false)
        .app().renderer.removeTexture(&.scenes[index]!.preview)
        .scenes.deleteAt(index)
        if selected
        {
            .active = Math.min(index, .scenes.isEmpty() ? 0 : .scenes.count - 1)
            .resumeScene(false)
        }
        elif index < .active
        {
            .active -= 1
        }

        .layoutScene()
        catch .primary.saveState()
    }

    mtd retireDocument(document: *ViewerWindow)
    {
        if .isHoveredDocument(document) do
            .hoveredDocument = null
        document.lens.close()
        if document != .primary do
            document.lens.destroy()
        document.closeInformation()
        document.closeFile()
        document.stopTimer(&document.startupTimer)
        document.hide()
        .retiring.add(document)
        if not .retireTimer do
            .retireTimer = .addTimer(20'ms)
    }

    mtd setLayout(layout: SceneLayout)
    {
        let scene = .scene()
        if not scene or not scene.supportsLayout(layout) do
            return
        .dismissVacancy()
        if layout != scene.layout and layout != .Single do
            scene.packCells()
        if layout == .Single and scene.views.count > 1
        {
            if not scene.maximized do
                .toggleMaximized()
            return
        }
        if scene.compared and layout != .SideBySide
        {
            .storeComparisonState()
            scene.compared = false
            .closeComparisonSheet()
        }

        scene.layout    = layout
        scene.maximized = false
        .showScene()
        .showMaximizedHint(false)
        catch .primary.saveState()
    }

    mtd toggleMaximized()
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 or .vacancy or .focusOnGrid do
            return
        scene.maximized = not scene.maximized
        if scene.maximized do
            .closeComparisonSheet()
        .layoutScene()
        .showMaximizedHint(scene.maximized)
        catch .primary.saveState()
    }

    mtd showScene()
    {
        .layoutScene()
        let document = .activeDocument()
        document.refreshTitle()
        document.refreshReadingAppearance()
        .tabs.invalidate()
        let focused = document.focusedWindow()
        if .focusOnGrid do
            .setFocus()
        elif focused != document and not document.isAncestorOf(focused) do
            document.setFocus()
    }

    mtd layoutScene()
    {
        if .mediaTransport == null do
            return
        let area         = .clientRect()
        let scene        = .scene()
        if not .isTiled() do
            .focusOnGrid = false
        var primaryShown = not scene
        if scene
        {
            for &view, index in scene.views where view.document
            {
                let visible = not (scene.maximized or scene.layout == .Single) or index == scene.active
                let player  = ScenePlayer.from(view.document)
                if player.film do
                    player.film.keepPlayingHidden = scene.maximized or scene.layout == .Single
                if player.sound do
                    player.sound.keepPlayingHidden = scene.maximized or scene.layout == .Single
                if visible do
                    view.document.show()
                else do
                    view.document.hide(keepActivities: true)
                if view.document == .primary do
                    primaryShown = visible
                if visible
                {
                    view.document.setPosition(.viewRect(scene, index))
                    if view.document.isExploring() do
                        view.document.teachHints(true)
                    view.document.layoutFileInfo()
                    view.document.applyLayout()
                }
                .updateMediaViewport(view.document)
            }
        }
        else
        {
            .primary.setPosition(area)
            .primary.applyLayout()
        }

        if primaryShown and .retiring.contains(.primary) and not .primary.pendingEmpty.isEmpty() do
            .primary.continueStartup()
        .primary.show(primaryShown)
        if .vacancy
        {
            .vacancy.setPosition(.gridCellRect(unwrap scene, .vacantCell))
            .vacancy.applyLayout()
        }
        .focusDelegate = .focusOnGrid ? null : .activeDocument()
        .updateMedia()
        .tabs.layoutTabs()
        .invalidate()
        .divider.place(.dividerRect())
        .switchBackdrop?.setPosition(area, computeLayout: false)
        .refreshComparison()
        if .pointerKnown do
            .updateHoveredDocument(.documentAtPointer(.pointerPosition))
        .comparisonSheet?.refresh()
    }

    mtd viewRect(scene: const *ViewerScene, index: u64)->Math.Rectangle
        => .gridCellRect(scene, index < scene.views.count ? scene.cellOf(index) : index)

    mtd gridCellRect(scene: const *ViewerScene, index: u64)->Math.Rectangle
    {
        var body = .clientRect()
        if scene.views.count <= 1 do
            return body

        let strip = .stripInset()
        body.y      += strip
        body.height = Math.max(body.height - strip, 0)
        if scene.maximized or scene.layout == .Single do
            return body

        let size     = scene.dimensions()
        let cols     = cast(u64, size.x)
        let row      = cast(f32, index / cols)
        let col      = cast(f32, index % cols)
        let gap: f32 = .isMediaScene() ? 2.0 : 1.0
        if scene.views.count == 2 and size.y == 1
        {
            let width = Math.round((body.width - gap) * scene.split)
            if not index do
                return {body.x, body.y, width, body.height}
            return {body.x + width + gap, body.y, body.width - width - gap, body.height}
        }

        if scene.views.count == 2 and size.x == 1
        {
            let height = Math.round((body.height - gap) * scene.split)
            if not index do
                return {body.x, body.y, body.width, height}
            return {body.x, body.y + height + gap, body.width, body.height - height - gap}
        }

        let width  = (body.width - (size.x - 1) * gap) / size.x
        let height = (body.height - (size.y - 1) * gap) / size.y
        let left   = Math.round(body.x + col * (width + gap))
        let top    = Math.round(body.y + row * (height + gap))
        return {left, top, Math.round(body.x + col * (width + gap) + width) - left,
                Math.round(body.y + row * (height + gap) + height) - top}
    }

    mtd activateFromPointer(child: *Wnd, evt: *MouseEvent)->bool
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 or evt.button != .Left do
            return false
        if .vacancy and evt.kind == .DoubleClick and (child == .vacancy or .vacancy.isOwnerOf(child))
        {
            .vacancy.chooseFile()
            return true
        }
        for view, index in scene.views where view.document and (view.document == child or view.document.isOwnerOf(child))
        {
            let document = view.document
            if child == document.cellCaption.close do
                return false
            .selectView(index)
            if evt.kind != .DoubleClick do
                return false
            let content = document.currentView
            let caption = child == document.cellCaption or child == document.cellCaption.title
            let frame   = ScenePlayer.from(document).film?.imageView == child
            if child == document or child == content or caption or frame
            {
                .toggleMaximized()
                return true
            }
            break
        }
        return false
    }

    mtd moveView(key: Input.Key, swap: bool)->bool
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 do
            return false
        let cols   = cast(s64, scene.maximized or scene.layout == .Single ? 1 : scene.dimensions().x)
        let single = scene.maximized or scene.layout == .Single
        let index  = cast(s64, single ? scene.active : (.vacancy ? .vacantCell : scene.cellOf(scene.active)))
        let column = index % cols
        let inGrid = not scene.maximized and scene.layout != .Single and cols > 1
        if .focusOnGrid and (key == .Left or key == .Right or key == .Up or key == .Down)
        {
            if not swap do
                .selectView(scene.active)
            return true
        }
        var target = index
        switch key
        {
        case .Left:
            if inGrid and column == 0 do
                return true
            target -= 1

        case .Right:
            if inGrid and column == cols - 1 do
                return true
            target += 1

        case .Up:
            target -= cols

        case .Down:
            target += cols

        default:
            return false
        }

        if target < 0 or target >= cast(s64, single ? scene.views.count : scene.cellCount()) do
            return true
        let cell = cast(u64, target)
        let view = single ? cell : scene.viewInCell(cell)
        if view == Swag.U64.Max
        {
            if swap and not .vacancy
            {
                scene.views[scene.active].cellPlusOne = cell + 1
                .showScene()
            }
            else do
                .focusVacancy(cell)
            return true
        }
        if swap and .vacancy
        {
            scene.views[view].cellPlusOne = .vacantCell + 1
            .focusVacancy(cell)
            return true
        }
        if swap do
            .swapSceneViews(scene.active, view)
        .selectView(view)
        return true
    }
}

impl IWnd for ViewerWorkspace
{
    mtd impl onStateEvent(evt: *StateEvent)
    {
        if evt.kind != .Init or evt.target != me
        {
            evt.accepted = false
            return
        }

        .primary.sendStateEvent(.Init)
        let files = #move .startupFiles
        if not .primary.smokeRunning and .scenes.isEmpty() do
            .restoreScenes(resume: files.isEmpty())
        if not files.isEmpty()
        {
            let selected = .scene()
            .openScene(files.toSlice(), .startupLayout)
            if selected and selected == .scene() do
                .resumeScene(false)
        }
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .layoutScene()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let scene = .scene()
        .paintedScene = scene?.recent orelse 0
        if scene and .isTiled() and not .comparisonVisible() do
            .paintGridDividers(evt.paintContext.painter, scene)
    }

    mtd impl onAfterPaint(evt: *PaintEvent)
    {
        .paintSceneChrome(evt.paintContext.painter)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .mediaTimer
        {
            .synchronizeMedia()
            .updateMediaTransport()
            if .comparisonVisible() do
                .comparison!.invalidate()
            return
        }

        if evt.timer == .maxHintTimer
        {
            .showMaximizedHint(false)
            return
        }

        if evt.timer != .retireTimer
        {
            evt.accepted = false
            return
        }

        for index in reversed(.retiring.count)
        {
            let document = .retiring[index]
            if document.choiceLoad.started and not document.choiceLoad.isDone() do
                continue
            if not document.pendingEmpty.isEmpty() do
                document.continueStartup()
            if document.choiceLoad.started or not document.pendingEmpty.isEmpty() do
                continue
            if document != .primary do
                document.destroy()
            .retiring.removeAtOrdered(index)
        }

        if .retiring.isEmpty() do
            .stopTimer(&.retireTimer)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if .routeSceneKey(evt, me) do
            return
        let document = .activeDocument()
        let focused  = .focusedWindow()
        if evt.kind == .Pressed and not document.lens.isOpen() and focused != document and not document.isAncestorOf(focused)
        {
            if let id = document.keyShortcut(evt.modifiers, evt.key)
            {
                document.sendCommandEvent(id)
                return
            }
        }

        evt.accepted = false
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Pressed and evt.button == .Left and .isTiled()
        {
            let scene = unwrap .scene()
            let cell = .vacantCellAt(scene, .surfaceToLocal(evt.surfacePos))
            if cell != Swag.U64.Max
            {
                .focusVacancy(cell)
                return
            }
        }
        if evt.kind == .Move or evt.kind == .Enter or evt.kind == .Leave do
            .trackViewHover(evt)
        evt.accepted = false
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        evt.accepted = .finishSoundAlignment(evt)
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .alignSound.task.cancel()
        .alignSound.wait()
        for scene in .scenes do
            .app().renderer.removeTexture(&scene!.preview)
    }

    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        evt.accepted = .dropFiles(evt)
    }
}
