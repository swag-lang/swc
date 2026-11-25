#global internal

using Core, Gui, Pixel

struct SceneTabs
{
    using wnd:      Wnd
    late workspace: *ViewerWorkspace
    items:          Array'Math.Rectangle
    hovered:        u64 = Swag.U64.Max
}

impl SceneTabs
{
    const Gap             = 6.0
    const HorizontalInset = 8.0
    const VerticalInset   = 5.0
    const CloseSize       = 14.0
    const CloseGap        = 3.0
    const ItemChromeWidth = 2 * HorizontalInset + CloseSize + CloseGap

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
        let margin  = .themeMetrics().floating_Inset
        let room    = Math.Rectangle{margin, caption.stripInset(), Math.max(caption.clientRect().width - 2 * margin, 0), .workspace.tabStripHeight()}
        .show(room.height > 0 and room.width > 0)
        if not .isLocallyVisible()
        {
            .hovered = Swag.U64.Max
            return
        }

        .setPosition(room, computeLayout: false)

        let font       = .theme().createDefaultFont(12)
        let scale      = .deviceScale()
        let labelLimit = Math.clamp(room.width - ItemChromeWidth, 0, 220)
        .items.clear()
        var width: f32
        for scene in .workspace.scenes
        {
            let name = .workspace.sceneName(unwrap scene)
            let textWidth = Math.ceil(Painter.measureStringSnapped(name, font, deviceScale: scale))
            let span = Math.min(textWidth, labelLimit) + ItemChromeWidth
            .items.add({y: VerticalInset, width: span, height: room.height - 2 * VerticalInset})
            width += span + Gap
        }

        width -= Gap
        var left = (room.width - width) * 0.5
        if left < 0
        {
            let selected = .workspace.active
            var before: f32
            for i in selected do
                before += .items[i].width + Gap
            left = Math.clamp(room.width * 0.5 - before - .items[selected].width * 0.5, room.width - width, 0)
        }

        for &item in .items
        {
            item.x = Math.round(left)
            left   += item.width + Gap
        }

        .invalidate()
    }

    mtd closeRect(item: Math.Rectangle)->Math.Rectangle =>
    {item.right() - HorizontalInset - CloseSize, item.vertCenter() - CloseSize * 0.5, CloseSize, CloseSize}

    private mtd showTabMenu(index: u64, position: Math.Point)
    {
        let owner = .workspace.activeDocument()
        let menu = MenuCtrl.createPopup(me, owner: owner)
        let scene = unwrap .workspace.scenes[index]
        var path, location: String
        if scene.views.count == 1 and not scene.views[0].path.isEmpty()
        {
            let view = &scene.views[0]
            path = view.path
            location = path
            let document = view.document
            let explorer = document?.explorer
            let folderTab = document ? document.isExploring() and not document.explorerTransition :
                                       not view.explorerState.path.isEmpty()
            if folderTab
            {
                let member = explorer ? explorer.requestedFolder.toString() : view.explorerState.folder.toString()
                let archive = (explorer?.listing.isArchive orelse view.explorerArchive) or member.count != 0
                if member.count do
                    location = Format.toString("%/%", path, member)
                owner.addLocationActions(menu, directory: not archive, archive: archive)
            }
            else do
                owner.addFileActions(menu)
            menu.addSeparator()
        }

        menu.addItems([TabCommands.New, TabCommands.NewGrid, TabCommands.OpenFile, TabCommands.OpenFolder])
        menu.addSeparator()
        menu.addItems([TabCommands.Close, TabCommands.CloseOthers, TabCommands.CloseAll])
        let chosen = menu.doModal(position, autoDestroy: true, dispatchCommand: false) orelse ""
        switch chosen
        {
        case TabCommands.Close:       .workspace.closeScene(index)
        case TabCommands.CloseOthers: .workspace.closeTabs(keep: index)
        case "":                     return
        default:
            if isPathMenuAction(chosen) do
                owner.runFileAction(chosen, chosen == ViewerCommands.CopyLocation ? location : path)
            else do
                discard owner.runCommand(chosen)
        }
    }

    mtd showsClose(index: u64)->bool => index == .workspace.active or index == .hovered

    mtd hit(position: Math.Point)->u64
    {
        for item, index in .items where item.contains(position) do
            return index

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
        let radius  = .themeMetrics().corner_Control
        let room    = .clientRect()
        for item, index in .items
        {
            let active  = index == .workspace.active
            let hovered = index == .hovered
            if active or hovered do
                painter.fillRoundRect(item, radius, radius, active ? colors.tabItem_ButtonSelected : colors.tabItem_ButtonHot)

            let name  = .workspace.sceneName(unwrap .workspace.scenes[index])
            let text  = Painter.elideString(name, font, item.width - ItemChromeWidth, .deviceScale())
            let edge  = Math.min(item.right(), room.width - item.x)
            let color = active ? colors.tabItem_SelectedText : hovered ? colors.tabItem_HotText : colors.tabItem_Text
            painter.drawString(item.x + HorizontalInset, font.opticalLineTop(item.vertCenter()), text, font, color.withAlphaF32(Math.clamp(edge / ItemChromeWidth, 0, 1)))
            if .showsClose(index)
            {
                let close = .closeRect(item)
                .theme().icon(.WndClose, CloseSize).paint(painter, close.x, close.y, colors.softText)
            }
        }
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
            elif evt.button == .Right do
                .showTabMenu(index, evt.surfacePos)

        default:
            evt.accepted = false
        }
    }
}

const CaptionActionCount = 12

struct CaptionActionLayout
{
    late action: *CaptionButton
    layoutX:    f32
    drawnX:     f32
    visible:    bool
}

impl ViewerWorkspace
{
    private mtd captionActions()->[CaptionActionCount] (*CaptionButton)
    {
        let primary = .primary
        return [primary.returnExplorerCaptionButton, primary.backCaptionButton,
                primary.forwardCaptionButton, primary.upCaptionButton,
                primary.refreshCaptionButton, primary.outlineCaptionButton,
                primary.informationCaptionButton, primary.viewerCaptionButton,
                .mediaPlayPause, .mediaTransport, .mediaLinks, .newTabButton]
    }

    mtd captureCaptionLayout()->[CaptionActionCount] CaptionActionLayout
    {
        var result: #returntype
        for action, index in .captionActions() do
            result[index] = {action, action.position.x, action.presentationRect().x, action.isLocallyVisible()}
        return result
    }

    mtd animateCaptionLayout(before: const [..] CaptionActionLayout)
    {
        for slot in before where slot.visible != slot.action.isLocallyVisible()
        {
            .surface!.wnd.sendResizeEvent()
            break
        }

        let animator = &.app().animator
        let metrics  = .themeMetrics()
        let center   = .surface!.wnd.clientRect().horzCenter()
        let duration = Time.Duration.fromSeconds(metrics.motion_PanelSeconds)
        let fade     = Time.Duration.fromSeconds(metrics.motion_QuickSeconds)
        let channel  = AnimationChannel.from("Scope.Caption.Layout")
        for slot, index in before
        {
            let action = slot.action
            if not action.isLocallyVisible() or (slot.visible and action.position.x == slot.layoutX) do
                continue

            var travel = slot.drawnX - action.position.x
            if not slot.visible
            {
                discard animator.fadeIn(action, fade)
                if action.presentationOpacity == 0 do
                    travel = action.position.horzCenter() < center ? -metrics.motion_AnchorTravel : metrics.motion_AnchorTravel
            }

            // A running offset is relative to its old slot. Replace it with the offset from the new slot.
            animator.cancel(.captionMoves[index])
            let offset = Math.Point{travel, 0}
            action.setPresentationOffset(offset)
            .captionMoves[index] = animator.animatePoint(action, channel, offset, {},
                                                         func(wnd, value) { wnd.setPresentationOffset(value) },
                                                         {duration: duration, easing: .EaseOut})
        }
    }

    private mtd bindSceneCaptionInput()
    {
        let holdInput: HookEvent = func|workspace = me|(control, evt)
        {
            if not workspace.sceneCaptionPending do
                return false
            if evt is MouseEvent as mouse
            {
                if mouse.kind == .Pressed do
                    return true
                if mouse.kind == .Released and control.mouseCapture() == control
                {
                    // Let the button release its capture without activating the old action.
                    var leave = mouse[]
                    leave.kind = .Leave
                    control.sendEvent(&leave)
                }
            }
            return false
        }

        for button in .captionActions() where button != .newTabButton do
            button.hookOnEvent = holdInput
    }

    mtd finishSceneCaption()
    {
        if not .sceneCaptionPending do
            return
        if let scene = .scene()
        {
            for view in scene.views
            {
                let document = view.document
                if not document or not document.pendingFile.isEmpty() or
                   not document.pendingEmpty.isEmpty() do
                    return
            }
        }

        .sceneCaptionPending = false
        let document = .activeDocument()
        document.refreshReadingAppearance()
        document.refreshTitle()
        .updateMedia()
    }

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
        let top   = .gridBody().y
        let body  = .clientRect()
        if .comparisonVisible()
        {
            let half       = body.width * 0.5
            let comparison = .comparison!.position
            let height     = Math.max(0, comparison.height - SceneComparison.FooterHeight)
            return {body.x + cast(f32, index) * half, comparison.y, half, height}
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

    mtd paneFocusRect(content: Math.Rectangle)->Math.Rectangle
    {
        if content.isEmpty() do
            return {}
        let inset  = Math.min(.themeMetrics().floating_Inset * 0.5, content.width * 0.25)
        let height = .themeMetrics().splitView_HotRule
        let y      = Math.round(content.y - (.paneFocusGutter() + height) * 0.5)
        return {content.x + inset, y, content.width - 2 * inset, height}
    }

    // The seams belong to the ground between cells, including vacant ones. The shared
    // title strip and any panels that open over the workspace keep their own ground.
    mtd paintGridDividers(painter: *Painter, scene: const *ViewerScene)
    {
        let grid = scene.dimensions()
        let cols = cast(u64, grid.x)
        let rows = cast(u64, grid.y)
        let body = .gridBody()
        let top  = body.y
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
                let rect = .vacancy ? .vacancy.position : .viewRect(scene, scene.active)
                painter.fillRect(.paneFocusRect(rect), colors.arc)
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
            if not compare.isPicture() or compare.mode != .Flip
            {
                var caption = compare.captionArea(scene.active)
                caption.x += compare.position.x
                caption.y += compare.position.y
                painter.fillRect(.paneFocusRect(caption), colors.arc)
            }
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
        if (.isTiled() or scene.views.isEmpty()) and not .comparisonVisible()
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
                let paths = evt.data.files.toSlice()
                let start = scene ? .vacantCellAt(scene, .surfaceToLocal(evt.surfacePos)) : Swag.U64.Max
                if onTabs or not .fillGrid(paths, start) do
                    .openScene(paths, .Auto)
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

    private mtd fillGrid(paths: const [..] String, start: u64)->bool
    {
        let scene = .scene()
        if not scene or not scene.manual or not .isTiled() or scene.compared or
           paths.count > scene.cellCount() - scene.views.count do
            return false

        .dismissVacancy()
        let first = start == Swag.U64.Max ? 0 : start
        var next: u64
        for offset in scene.cellCount()
        {
            let cell = (first + offset) % scene.cellCount()
            if scene.viewInCell(cell) != Swag.U64.Max do
                continue
            scene.views.add({path: paths[next], cellPlusOne: cell + 1})
            if next == 0 do
                scene.active = scene.views.count - 1
            let view = scene.views.backPtr()
            ViewerWorkspace.attachDocument(me, view, remember: true)
            next += 1
            if next == paths.count do
                break
        }

        .showScene()
        catch .primary.saveState()
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
        if shortcut == TabCommands.New do
            return document.runCommand(shortcut)
        let swap = Slice.findLinear(SceneCommands.SwapDirections, shortcut) != Swag.U64.Max
        if source is EditBox or .focusedWindow() is EditBox
        {
            if document.searchComparison and document.searchBox.hasFocus() and .routeComparisonKey(evt, source) do
                return true
            return shortcut == SceneCommands.Maximize or swap
        }
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
