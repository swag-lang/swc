#global internal

using Core, Gui, Pixel

struct SceneTabs
{
    using wnd:      Wnd
    late workspace: *ViewerWorkspace
    items:          Array'Math.Rectangle
    hovered:        u64 = Swag.U64.Max
    underline:      Math.Rectangle
    previous:       Math.Rectangle
    slideStarted:   u64
    slideTimer:     *Timer?
}

impl SceneTabs
{
    const Gap       = 28.0
    const CloseSize = 14.0

    func create(workspace: *ViewerWorkspace)->*SceneTabs
    {
        let result = Wnd.create'SceneTabs(unwrap workspace.surface?.wnd, "scope.scene.tabs")
        result.workspace       = workspace
        result.backgroundStyle = .Transparent
        result.focusPolicy     = .Click
        result.hide()
        return result
    }

    mtd layoutTabs()
    {
        let caption = unwrap .surface?.wnd
        let room    = caption.captionContentRect()
        .show(.workspace.scenes.count >= 2 and room.height > 0 and room.width > 0)
        if not .isLocallyVisible()
        {
            .stopTimer(&.slideTimer)
            .underline = {}
            return
        }

        .setPosition(room, computeLayout: false)

        let font = .theme().createDefaultFont(12)
        .items.clear()
        var width: f32
        for scene in .workspace.scenes
        {
            let name = .workspace.sceneName(unwrap scene)
            let span = Math.min(Painter.measureString(name, font).width, 220)
            .items.add({width: span, height: room.height})
            width += span + Gap
        }

        width -= Gap
        let selected = .workspace.active
        var left     = (room.width - width) * 0.5
        let endSpace = Gap * 0.5 + 1
        if left < endSpace
        {
            var before: f32
            for i in selected do
                before += .items[i].width + Gap
            let first = Math.min(0, room.width - width - endSpace)
            left = Math.clamp(room.width * 0.5 - before - .items[selected].width * 0.5, first, 0)
        }

        for &item in .items
        {
            item.x = Math.round(left)
            left   += item.width + Gap
        }

        let active = .items[selected]
        let next   = Math.Rectangle{active.x, room.height - 12, active.width, 2}
        if .underline != next
        {
            .previous     = .underline.width > 0 ? .displayedUnderline() : next
            .underline    = next
            .slideStarted = Time.monotonicMicroseconds()
            if .app().isReducedMotion() do
                .stopTimer(&.slideTimer)
            elif not .slideTimer and .previous != next do
                .slideTimer = .addTimer(16'ms)
        }

        .invalidate()
    }

    private mtd displayedUnderline()->Math.Rectangle
    {
        var mark = .underline
        if .slideTimer
        {
            let seconds   = cast(f32, Time.monotonicMicroseconds() - .slideStarted) / 1_000_000
            let remaining = 1 - Math.clamp(seconds / .themeMetrics().motion_PageSeconds, 0, 1)
            let blend     = remaining * remaining
            mark.x     += (.previous.x - mark.x) * blend
            mark.width += (.previous.width - mark.width) * blend
        }

        return mark
    }

    private mtd closeRect(item: Math.Rectangle)->Math.Rectangle =>
    {item.right() + 1, item.vertCenter() - CloseSize * 0.5, CloseSize, CloseSize}

    mtd showsClose(index: u64)->bool => index == .workspace.active or index == .hovered

    mtd hit(position: Math.Point)->u64
    {
        for rect, index in .items
        {
            let target = Math.Rectangle{rect.x - Gap * 0.5, 0, rect.width + Gap + 1, rect.height}
            if target.contains(position) do
                return index
        }

        return Swag.U64.Max
    }
}

impl IWnd for SceneTabs
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let font    = .theme().createDefaultFont(12)
        let colors  = .themeColors()
        let room    = .clientRect()
        for item, index in .items
        {
            let name   = .workspace.sceneName(unwrap .workspace.scenes[index])
            let text   = Painter.elideString(name, font, item.width, .deviceScale())
            let active = index == .workspace.active
            let edge   = Math.min(item.right(), room.width - item.x)
            let color  = active ? colors.text : colors.faintText.withAlphaF32(Math.clamp(edge / 28, 0, 1))
            painter.drawString(item.x, font.opticalLineTop(item.vertCenter()), text, font, color)
            if .showsClose(index)
            {
                let close = .closeRect(item)
                .theme().icon(.WndClose, CloseSize).paint(painter, close.x, close.y, colors.softText)
            }
        }

        painter.fillRect(.displayedUnderline(), colors.arc)
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        let elapsed = cast(f32, Time.monotonicMicroseconds() - .slideStarted) / 1_000_000
        if elapsed >= .themeMetrics().motion_PageSeconds do
            .stopTimer(&.slideTimer)
        .invalidate()
    }

    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        evt.accepted = .workspace.dropFiles(evt, onTabs: true)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let point = .surfaceToLocal(evt.surfacePos)
        let index = .hit(point)
        switch evt.kind
        {
        case .Accept:
            evt.accepted = index < .items.count

        case .Move, .Enter, .Leave:
            .hovered = evt.kind == .Leave ? Swag.U64.Max : index
            .invalidate()

        case .Pressed where index < .items.count:
            let item = .items[index]
            var close = .closeRect(item)
            close.inflate(.themeMetrics().wnd_CaptionButtonMargin)
            if evt.button == .Middle or evt.button == .Left and .showsClose(index) and close.contains(point) do
                .workspace.closeScene(index)
            elif evt.button == .Left do
                .workspace.selectScene(index)

        default:
            evt.accepted = false
        }
    }
}

impl ViewerWorkspace
{
    mtd dividerRect(columns = true, track = 1'u64)->Math.Rectangle
    {
        let scene = .scene()
        if not scene or not .isTiled() or scene.compared do
            return {}
        let grid  = scene.dimensions()
        if track >= cast(u64, columns ? grid.x : grid.y) do
        return {}
        let body   = .gridBody()
        let band   = .themeMetrics().splitView_BarSize
        let offset = (.gridGap() - band) * 0.5
        if columns
        {
            let cell = .gridCellRect(scene, track - 1)
            return {cell.right() + offset, body.y, band, body.height}
        }

        let cell = .gridCellRect(scene, (track - 1) * cast(u64, grid.x))
        return {body.x, cell.bottom() + offset, body.width, band}
    }

    mtd stopDividerDrags()
    {
        for index in .columnDividers.count
        {
            .columnDividers[index]!.stopDrag()
            .rowDividers[index]!.stopDrag()
        }
    }

    mtd cellRect(scene: const *ViewerScene, index: u64)->Math.Rectangle
    {
        let top   = .stripInset()
        let body  = .clientRect()
        if .comparisonVisible()
        {
            let half   = body.width * 0.5
            let height = Math.max(0, .comparison!.position.bottom() - SceneComparison.FooterHeight - top)
            return {body.x + cast(f32, index) * half, top, half, height}
        }

        var rect  = .viewRect(scene, index)
        rect.intersect({0, top, body.width, Math.max(0, body.bottom() - top)})
        return rect
    }

    mtd dropRect(scene: const *ViewerScene, index: u64)->Math.Rectangle
    {
        var rect = .cellRect(scene, index)
        let compare = .comparison
        if not compare or not compare.isLocallyVisible() or not compare.isPicture() do
            return rect
        if compare.mode == .Flip
        {
            if (index != 0) != compare.shownRight do
                return {}
            rect.x     = 0
            rect.width = .clientRect().width
            return rect
        }
        if compare.mode != .Curtain do
            return rect

        let split = Math.round(.clientRect().width * compare.separator)
        if index == 0
        {
            rect.width = split
        }
        else
        {
            rect.width = rect.right() - split
            rect.x     = split
        }

        return rect
    }

    mtd paintDropHighlight(painter: *Painter, scene: const *ViewerScene)
    {
        let index = .dropView
        if index == Swag.U64.Max do
            return
        let metrics = .themeMetrics()
        let view    = scene.viewInCell(index)
        var rect    = view == Swag.U64.Max ? .gridCellRect(scene, index) : .dropRect(scene, view)
        rect.inflate(-metrics.wnd_CaptionButtonMargin)
        if rect.width <= 0 or rect.height <= 0 do
            return
        var pen = Pen.createDash(.Dash, .themeColors().arc, metrics.focusRing_Size)
        pen.borderPos = .Inside
        painter.drawRoundRect(rect, metrics.corner_Control, metrics.corner_Control, pen)
    }

    private mtd paintCellFocus(painter: *Painter, rect: Math.Rectangle)
    {
        let metrics = .themeMetrics()
        var pen = Pen.createSolid(.themeColors().arc, metrics.fileTile_RingWidth)
        pen.borderPos = .Inside
        painter.drawRoundRect(rect, metrics.corner_Control, metrics.corner_Control, pen)
    }

    // The seams belong to the ground between cells, including vacant ones. The shared
    // title strip and any panels that open over the workspace keep their own ground.
    mtd paintGridDividers(painter: *Painter, scene: const *ViewerScene)
    {
        let grid = scene.dimensions()
        let cols = cast(u64, grid.x)
        let rows = cast(u64, grid.y)
        let body = .clientRect()
        let top = .stripInset()
        let ink = .themeColors().line
        for col in 1 until cols
        {
            let x = .gridCellRect(scene, col - 1).right()
            painter.fillRect(x, top, 1, body.bottom() - top, ink)
        }
        for row in 1 until rows
        {
            let y = .gridCellRect(scene, (row - 1) * cols).bottom()
            painter.fillRect(body.x, y, body.width, 1, ink)
        }
    }

    mtd paintSceneChrome(painter: *Painter)
    {
        let scene = .scene()
        if not scene or .activeDocument().lens.isOpen() do
            return

        let colors  = .themeColors()
        if .usesCellCaptions()
        {
            let metrics  = .themeMetrics()
            let inset    = metrics.floating_Inset
            if .isTiled() and not .focusOnGrid
            {
                let rect = .vacancy ? .gridCellRect(scene, .vacantCell) : .viewRect(scene, scene.active)
                .paintCellFocus(painter, rect)
            }
            if scene.maximized
            {
                let area   = .clientRect()
                let size   = 5.0
                let grid   = scene.dimensions(useMaximized: false)
                let cols   = cast(u64, grid.x)
                let left   = area.right() - 20 - grid.x * (size + 2)
                let bottom = .maximizedWorkBottom() - inset - grid.y * (size + 2)
                for index in cast(u64, grid.x * grid.y)
                {
                    let x   = left + cast(f32, index % cols) * (size + 2)
                    let y   = bottom + cast(f32, index / cols) * (size + 2)
                    let ink = index == scene.cellOf(scene.active) ? colors.arc : (scene.viewInCell(index) != Swag.U64.Max ? colors.strongLine : colors.line)
                    painter.fillRect(x, y, size, size, ink)
                }
            }
        }

        if .comparisonVisible() and not .focusOnGrid
        {
            let compare = unwrap .comparison
            if compare.hasSeparateSides() do
                .paintCellFocus(painter, .cellRect(scene, scene.active))
            elif not compare.isPicture() or compare.mode != .Flip do
                .paintCellFocus(painter, compare.captionArea(scene.active))
        }

        .paintDropHighlight(painter, scene)
    }
}

struct SceneDivider
{
    using wnd:      Wnd
    late workspace: *ViewerWorkspace
    track:          u64
    columns:        bool
    hot:            bool
    dragging:       bool
    grabOffset:     f32
}

impl SceneDivider
{
    func create(workspace: *ViewerWorkspace, track: u64, columns: bool)->*SceneDivider
    {
        let result = Wnd.create'SceneDivider(workspace, "scope.scene.divider")
        result.workspace       = workspace
        result.track           = track
        result.columns         = columns
        result.cursor          = Cursor.from(columns ? CursorShape.ResizeHorizontal : CursorShape.ResizeVertical)
        result.backgroundStyle = .Transparent
        result.wndFlags.add(.TopMost)
        result.hide()
        return result
    }

    mtd place(bounds: Math.Rectangle)
    {
        if bounds.isEmpty()
        {
            .stopDrag()
            .hot = false
            .hide()
            return
        }

        .setPosition(bounds, computeLayout: false)
        .show()
    }

    mtd stopDrag()
    {
        if not .dragging do
            return
        .dragging = false
        if .mouseCapture() == me do
            .releaseMouse()
        .invalidate()
    }
}

impl IWnd for SceneDivider
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if not .hot and not .dragging do
            return
        let area = .clientRect()
        let size = .themeMetrics().splitView_HotRule
        let line = .columns ? Math.Rectangle{Math.floor(area.horzCenter() - size * 0.5), 0, size, area.height} :
                   Math.Rectangle{0, Math.floor(area.vertCenter() - size * 0.5), area.width, size}
        evt.paintContext.painter.fillRect(line, .themeColors().arc)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let scene = .workspace.scene()
        let point = .workspace.surfaceToLocal(evt.surfacePos)
        let hit   = scene and .isLocallyVisible() and .position.contains(point)
        switch evt.kind
        {
        case .Accept:
            evt.accepted = hit or .dragging and .mouseCapture() == me

        case .Enter, .Leave:
            .hot = evt.kind == .Enter
            .invalidate()

        case .Pressed where hit and evt.button == .Left:
            .dragging = true
            .grabOffset = .columns ? point.x - .position.horzCenter() : point.y - .position.vertCenter()
            .captureMouse()
            .invalidate()

        case .Released where .dragging and evt.button == .Left:
            .stopDrag()
            catch .workspace.primary.saveState()

        case .DoubleClick where hit and evt.button == .Left:
            let grid  = scene!.dimensions()
            let count = cast(u64, .columns ? grid.x : grid.y)
            if grid.x == 1 or grid.y == 1 do
                scene.split = 0.5
            elif .columns do
                scene.columnCuts.clear(count)
            else do
                scene.rowCuts.clear(count)
                .workspace.layoutScene()
            catch .workspace.primary.saveState()

        case .Move where .dragging:
            if not scene or .mouseCapture() != me
            {
                .stopDrag()
                evt.accepted = false
                return
            }

            let grid  = scene.dimensions()
            let count = cast(u64, .columns ? grid.x : grid.y)
            let area  = .workspace.gridBody()
            let span  = .columns ? area.width : area.height
            let gap   = .workspace.gridGap()
            let at    = (.columns ? point.x - area.x : point.y - area.y) - .grabOffset
            let ratio = (at - (cast(f32, .track) - 0.5) * gap) / Math.max(span - cast(f32, count - 1) * gap, 1)
            if grid.x == 1 or grid.y == 1 do
            scene.split = Math.clamp(ratio, 0.18, 0.82)
            elif .columns do
                scene.columnCuts.resize(.track, count, ratio)
            else do
                scene.rowCuts.resize(.track, count, ratio)
            .workspace.layoutScene()

        default:
            evt.accepted = false
        }
    }
}

impl ViewerWorkspace
{
    mtd trackViewHover(evt: *MouseEvent)
    {
        let position = evt.surfacePos
        let moved    = not .pointerKnown or position != .pointerPosition
        let document = .documentAtPointer(position)
        .updateHoveredDocument(document)
        if evt.kind == .Leave do
            return
        .pointerKnown    = true
        .pointerPosition = position
        if moved and document and document.usesTimedViewerBar() do
            document.notePointer(position, moved: true)
    }

    mtd documentAtPointer(position: Math.Point)->*ViewerWindow?
    {
        let scene = .scene()
        if scene
        {
            let point = .surfaceToLocal(position)
            for view, index in scene.views where view.document and view.document.isLocallyVisible()
            {
                if .cellRect(scene, index).contains(point) do
                    return view.document
            }
        }
        return null
    }

    mtd updateHoveredDocument(document: *ViewerWindow?)
    {
        if document == .hoveredDocument do
            return
        let previous = .hoveredDocument
        .hoveredDocument = document
        if previous and .usesCellCaptions() and previous.usesTimedViewerBar() do
            previous.concealViewerBar()
    }

    mtd isHoveredDocument(document: *ViewerWindow?)->bool => .hoveredDocument == document

    private mtd maximizedWorkBottom()->f32
    {
        let document = .activeDocument()
        var bottom = document.documentArea().bottom()
        if document.currentCommands do
            bottom = Math.min(bottom, document.viewerBar.position.y)
        return .surfaceToLocal(document.localToSurface(Math.Point{0, bottom})).y
    }

    mtd layoutMaximizedHint()
    {
        if .maxHint and (.scene()?.maximized orelse false)
        {
            .maxHint.margin.w = Math.max(0, .clientRect().bottom() - .maximizedWorkBottom())
            .maxHint.itf.onLayout()
        }
    }

    mtd showMaximizedHint(show: bool)
    {
        if not show
        {
            if .maxHint do
                discard .app().animator.leave(.maxHint)
            .stopTimer(&.maxHintTimer)
            return
        }

        if not .maxHint do
            .maxHint = HintLine.create(me, "scope.scene.maximized.hint")
        let hint = .maxHint
        let text = appStrings()
        hint.clearHints()
        hint.addHint(Input.formatKeyShortcut(.None, .Escape), text.scene_HintReturn)
        hint.addHint(Input.formatKeyShortcut(.Alt, .Left), text.scene_HintNavigate)
        hint.addHint(Input.formatKeyShortcut(.Control, .Space), text.ui_HintLens)
        hint.setGrounded(true)
        .layoutMaximizedHint()
        hint.bringToFront()
        discard .app().animator.arrive(hint)
        .stopTimer(&.maxHintTimer)
        .maxHintTimer = .addTimer(ViewerWindow.ViewerBarLinger)
    }

    mtd clearDropHighlight()
    {
        if .dropView != Swag.U64.Max
        {
            .dropView = Swag.U64.Max
            .invalidate()
            .refreshComparison()
        }

        .primary.dropHighlight.hide()
    }

    mtd vacantCellAt(scene: const *ViewerScene, point: Math.Point)->u64
    {
        if .isTiled() and not .comparisonVisible()
        {
            for cell in scene.cellCount() where scene.viewInCell(cell) == Swag.U64.Max and .gridCellRect(scene, cell).contains(point) do
                return cell
        }
        return Swag.U64.Max
    }

    mtd dropFiles(evt: *DragDropEvent, onTabs = false)->bool
    {
        if evt.kind == .Leave
        {
            .clearDropHighlight()
            return true
        }

        let effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
        if not evt.data.hasFiles() or evt.data.files.count > MaxViews or effect == .None
        {
            .clearDropHighlight()
            return false
        }

        .closeSwitcher(choose: false)

        let scene = .scene()
        let one   = evt.data.files.count == 1
        var index = Swag.U64.Max
        if scene and one and not onTabs
        {
            let point = .surfaceToLocal(evt.surfacePos)
            for view, i in scene.views where (view.document?.isLocallyVisible() orelse false)
            {
                let rect = .dropRect(scene, i)
                if not rect.isEmpty() and rect.contains(point)
                {
                    index = scene.cellOf(i)
                    break
                }
            }

            if index == Swag.U64.Max do
                index = .vacantCellAt(scene, point)
            if index == Swag.U64.Max
            {
                .clearDropHighlight()
                return true
            }
        }

        if evt.kind == .Drop
        {
            .clearDropHighlight()
            if not one
            {
                .openScene(evt.data.files.toSlice(), .Auto)
            }
            elif index != Swag.U64.Max
            {
                let view = scene!.viewInCell(index)
                if view == Swag.U64.Max
                {
                    .focusVacancy(index)
                    .activeDocument().queueFile(evt.data.files[0])
                }
                else
                {
                    .dismissVacancy()
                    .replaceDocument(view, evt.data.files[0])
                }
            }
            else
            {
                .openDocument(evt.data.files[0])
            }
        }
        elif index == Swag.U64.Max
        {
            .clearDropHighlight()
            if not scene do
                .primary.dropHighlight.showTarget(false)
        }
        elif .dropView != index
        {
            .dropView = index
            .invalidate()
        }

        evt.effect = effect
        return true
    }

    mtd routeSceneKey(evt: *KeyEvent, source: *Wnd)->bool
    {
        if evt.kind == .Released and
           (evt.key == .Control or evt.key == .LControl or evt.key == .RControl) and
           .switcher
        {
            .closeSwitcher(choose: true)
            return true
        }

        if evt.kind == .Released and
           .mediaPlayKeyDown and
           (evt.key == .Space or evt.key == .MediaPlayPause)
        {
            .mediaPlayKeyDown = false
            return true
        }

        if evt.kind != .Pressed do
            return false
        let cycle = evt.key == .Tab and (evt.modifiers == .Control or evt.modifiers == .CtrlShift)
        let document = .activeDocument()
        if document.lens.isOpen() do
            return cycle or (evt.modifiers != .None and document.keyShortcut(evt.modifiers, evt.key) == ViewerCommands.Close)
        if cycle and .scenes.count > 1
        {
            .cycleSwitcher(evt.modifiers.has(.Shift))
            return true
        }

        if .switcher
        {
            if evt.key == .Escape do
                .closeSwitcher(choose: false)
            return true
        }

        if .focusOnGrid and evt.key == .Tab and (evt.modifiers == .None or evt.modifiers == .Shift)
        {
            .selectView(.scene()!.active)
            return true
        }

        let shortcut = document.keyShortcut(evt.modifiers, evt.key) orelse ""
        let swap     = Slice.findLinear(SceneCommands.SwapDirections, shortcut) != Swag.U64.Max
        if source is EditBox or .focusedWindow() is EditBox do
            return shortcut == SceneCommands.Maximize or swap
        if .vacancy and evt.modifiers == .None and evt.key == .Return
        {
            .vacancy.chooseFile()
            return true
        }

        if swap do
            return document.runCommand(shortcut)
        if evt.modifiers == .Alt and .moveView(evt.key, swap: false) do
            return true
        if .routeComparisonKey(evt, source) or .routeSceneMediaKey(evt, source) do
            return true
        if (document.informationOpen() or (.scene()?.maximized orelse false)) and
           shortcut == ViewerCommands.Dismiss do
            return document.runCommand(ViewerCommands.Dismiss)

        return false
    }
}
