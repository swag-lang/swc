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
    offset:    f64
    behind:    bool
}

struct ViewerScene
{
    views:           Array'SceneView
    layout:          SceneLayout = .Auto
    active:          u64
    recent:          u64
    split:           f32         = 0.5
    maximized:       bool
    compared:        bool
    linked:          bool
    links:           SceneLinks
    comparisonState: SceneComparisonState
    preview:         Texture
}

impl ViewerScene
{
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

    mtd swapViews(first, second: u64)
    {
        var view = #move .views[first]
        .views[first]  = #move .views[second]
        .views[second] = #move view
        .links.leader  = remapSwappedView(.links.leader, first, second)
        .links.solo    = remapSwappedView(.links.solo, first, second)
    }

    mtd const name(theme: *Theme)->String
    {
        if .views.isEmpty() do
            return ProductName
        let first: string = Path.fileName(.views[0].path) orelse .views[0].path
        if .views.count == 1 do
            return first
        if .views.count == 2
        {
            let second: string = Path.fileName(.views[1].path) orelse .views[1].path
            return Format.toString("% ↔ %", first, second)
        }

        for view in .views where theme.fileGlyph(view.path, false).index != cast(s32, ThemeIcons.FileVideo) do
            return Format.toString(appStrings().scene_Files, .views.count)
        return Format.toString(appStrings().scene_Videos, .views.count)
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

    late primary: *ViewerWindow
    late tabs:    *SceneTabs
    late overlay: *SceneOverlay

    scenes:           ArrayPtr'ViewerScene
    active:           u64
    activation:       u64
    paintedScene:     u64
    retiring:         Array'(*ViewerWindow)
    retireTimer:      *Timer?
    restored:         Array'SavedScene
    restoredTab:      u64
    switchOrder:      Array'u64
    switchCursor:     u64
    switcher:         *FloatingPanel?
    switchBackdrop:   *Wnd?
    compactMedia:     bool
    maxHint:          *HintLine?
    maxHintTimer:     *Timer?
    comparison:       *SceneComparison?
    comparisonScene:  *ViewerScene?
    comparisonSheet:  *ComparisonSheet?
    transport:        *SceneTransport?
    alignSound:       SceneSoundAlignment
    dropTarget:       SceneDropTarget
    dragging:         bool
    splitDrag:        bool
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
        result.backgroundStyle = .Application
        result.surface!.setView(result)
        result.primary             = ViewerWindow.create(result, #move index, result)
        result.primary.focusPolicy = .Click
        result.tabs                = SceneTabs.create(result)
        result.overlay             = SceneOverlay.create(result)
        result.hookOnChildEvent    = func|workspace = result|(_, evt)
        {
            switch evt
            {
            case KeyEvent as key:
                return key.target != null and workspace.routeSceneKey(key, key.target)

            case MouseEvent as pointer where pointer.kind == .Move or pointer.kind == .Enter:
                workspace.noteMediaPointer()
                if pointer.kind == .Move and
                   pointer.target and
                   workspace.activeDocument().isOwnerOf(pointer.target) do
                    workspace.linkReading(workspace.activeDocument())

            case MouseEvent as pointer where pointer.kind == .Pressed or pointer.kind == .DoubleClick:
                if pointer.target do
                    workspace.activateFromPointer(pointer.target, pointer)
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
        let scene = .scene()
        if not scene or scene.active >= scene.views.count do
            return .primary
        return scene.views[scene.active].document orelse .primary
    }

    mtd documentCount()->u64 => .scene()?.views.count orelse 0

    func attachDocument(workspace: *ViewerWorkspace, view: *SceneView, remember: bool)
    {
        let document = ViewerWindow.create(workspace, createViewerPluginRegistry(), workspace)
        view.document        = document
        document.focusPolicy = .Click
        if view.readState do
            document.readingState = view.reading
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
        next.layout   = layout
        next.compared = compare and paths.count == 2
        next.linked   = next.compared or paths.count > 1 and layout != .SideBySide and allMedia(.theme(), paths)
        for path in paths do
            next.views.add({path: path[]})
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

    mtd insertDocument(path: string, target: SceneDropTarget)
    {
        let scene = .scene()
        if not scene or target == .NewTab
        {
            .openDocument(path)
            return
        }

        if target == .Replace
        {
            let view = &scene.views[scene.active]
            view.path      = path
            view.readState = false
            view.document!.queueFile(path)
            .layoutScene()
            return
        }

        if scene.views.count >= MaxViews do
            return
        let index = target == .Left ? scene.active : scene.active + 1
        scene.views.insertAt(index, SceneView{path: String.from(path)})
        scene.active    = index
        scene.layout    = scene.views.count == 2 ? (target == .Below ? .Stacked : .SideBySide) : .Auto
        scene.maximized = false
        scene.compared  = false
        scene.linked    = false
        ViewerWorkspace.attachDocument(me, &scene.views[index], remember: true)
        .showScene()
    }

    mtd updateDocumentPath(document: *ViewerWindow)
    {
        let scene = .scene()
        if not scene do
            return
        for &view in scene.views where view.document == document and not document.currentFile.isEmpty() do
            view.path = document.currentFile
        .tabs.invalidate()
    }

    mtd suspendScene(capturePreview = true)
    {
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
        if not document or document.activeChoiceIndex >= document.instances.count do
            return
        let session = &document.instances[document.activeChoiceIndex]
        if not session.view or document.readingState.restoring do
            return
        view.reading.capture(session, document.choices[document.activeChoiceIndex].key, document.searchBox.text())
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

    mtd selectView(index: u64)
    {
        let scene = .scene()
        if not scene or index >= scene.views.count or index == scene.active do
            return
        let previous = .activeDocument()
        previous.hideSearch()
        previous.closeInformation()
        previous.concealViewerBar()
        scene.active = index
        .showScene()
    }

    mtd closeView()
    {
        let scene = .scene()
        if not scene
        {
            .primary.closeFile()
            return
        }

        if scene.views.count == 1
        {
            .closeScene(.active)
            return
        }

        let index = scene.active
        .retireDocument(unwrap scene.views[index].document)
        scene.views.removeAtOrdered(index)
        scene.links.leader = remapClosedView(scene.links.leader, index)
        scene.links.solo   = remapClosedView(scene.links.solo, index)
        scene.active       = Math.min(index, scene.views.count - 1)
        scene.compared     = false
        scene.maximized    = false
        .showScene()
        catch .primary.saveState()
    }

    mtd closeScene(index: u64)
    {
        if index >= .scenes.count do
            return
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
        if not scene do
            return
        scene.layout    = layout
        scene.maximized = false
        .layoutScene()
        catch .primary.saveState()
    }

    mtd toggleMaximized()
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 do
            return
        scene.maximized = not scene.maximized
        .layoutScene()
        .showMaximizedHint(scene.maximized)
    }

    mtd showScene()
    {
        .layoutScene()
        let document = .activeDocument()
        document.refreshTitle()
        document.refreshReadingAppearance()
        .tabs.invalidate()
        document.setFocus()
    }

    mtd layoutScene()
    {
        if .primary == null or .overlay == null do
            return
        let area         = .clientRect()
        let scene        = .scene()
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
                view.document.show(visible)
                if view.document == .primary do
                    primaryShown = visible
                if visible
                {
                    view.document.setPosition(.viewRect(scene, index))
                    view.document.updateDocumentInsets()
                    view.document.applyLayout()
                    .updateMediaViewport(view.document)
                }
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
        .tabs.layoutTabs()
        .overlay.setPosition(area, computeLayout: false)
        .overlay.bringToFront()
        .overlay.invalidate()
        .switchBackdrop?.setPosition(area, computeLayout: false)
        .refreshComparison()
        .updateMedia()
        .comparisonSheet?.layoutSheet()
        .comparisonSheet?.refresh()
    }

    mtd viewRect(scene: const *ViewerScene, index: u64)->Math.Rectangle
    {
        var body = .clientRect()
        if scene.views.count <= 1 do
            return body

        let strip = .isMediaScene() ? 0 : .stripInset()
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

    mtd activateFromPointer(child: *Wnd, evt: *MouseEvent)
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 or evt.button != .Left do
            return
        for view, index in scene.views where view.document and (view.document == child or view.document.isOwnerOf(child))
        {
            .selectView(index)
            if evt.kind == .DoubleClick and (child == view.document or view.document.currentView == child or .isMediaScene()) do
                .toggleMaximized()
            return
        }
    }

    mtd moveView(key: Input.Key, swap: bool)->bool
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 do
            return false
        let cols   = cast(s64, scene.maximized or scene.layout == .Single ? 1 : scene.dimensions().x)
        let index  = cast(s64, scene.active)
        let column = index % cols
        let inGrid = not scene.maximized and scene.layout != .Single and cols > 1
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

        if target < 0 or target >= cast(s64, scene.views.count) do
            return true
        if swap do
            scene.swapViews(scene.active, cast(u64, target))
        .selectView(cast(u64, target))
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
        if .scenes.isEmpty() do
            .restoreScenes()
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .layoutScene()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        .paintedScene = .scene()?.recent orelse 0
        if .isMediaScene() do
            evt.paintContext.painter.fillRect(.clientRect(), Color.fromArgb(Argb.Black))
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .maxHintTimer
        {
            .maxHint?.hide()
            .stopTimer(&.maxHintTimer)
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
        evt.accepted = .routeSceneKey(evt, me)
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

private func allMedia(theme: *Theme, paths: const [..] String)->bool
{
    for path in paths
    {
        let kind = theme.fileGlyph(path[], false).index
        if kind != cast(s32, ThemeIcons.FileVideo) and kind != cast(s32, ThemeIcons.FileAudio) do
            return false
    }

    return true
}
