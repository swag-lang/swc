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
            let name = scene!.name(.theme())
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
            let name   = .workspace.scenes[index]!.name(.theme())
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
    mtd dividerRect()->Math.Rectangle
    {
        let scene = .scene()
        if not scene or
           scene.views.count != 2 or
           scene.maximized or
           scene.layout == .Single or
           scene.compared do
            return {}
        let grid  = scene.dimensions()
        let first = .viewRect(scene, 0)
        if grid.y == 1 do
            return {first.right() - 3, first.y, 7, first.height}
        if grid.x == 1 do
            return {first.x, first.bottom() - 3, first.width, 7}
        return {}
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
        if index >= scene.views.count do
            return
        let metrics = .themeMetrics()
        var rect    = .dropRect(scene, index)
        rect.inflate(-metrics.wnd_CaptionButtonMargin)
        if rect.width <= 0 or rect.height <= 0 do
            return
        var pen = Pen.createSolid(.themeColors().arc, metrics.focusRing_Size)
        pen.borderPos = .Inside
        painter.drawRoundRect(rect, metrics.corner_Control, metrics.corner_Control, pen)
    }
    mtd paintSceneChrome(painter: *Painter)
    {
        let scene = .scene()
        if not scene or .activeDocument().lens.isOpen() do
            return

        let colors  = .themeColors()
        let font    = .theme().createDefaultFont(12)
        if scene.views.count > 1 and not .comparisonVisible()
        {
            let divider = .dividerRect()
            if divider.width > 0
            {
                let vertical = scene.dimensions().y == 1
                let line     = vertical ? Math.Rectangle{divider.x + 3, divider.y, 1, divider.height} :
                               Math.Rectangle{divider.x, divider.y + 3, divider.width, 1}
                painter.fillRect(line, colors.line)
            }

            let metrics  = .themeMetrics()
            let inset    = metrics.floating_Inset
            let relative = scene.linked and scene.links.mode == .Relative and .isMediaScene()
            for view, index in scene.views where view.document and view.document.isLocallyVisible()
            {
                let rect       = .viewRect(scene, index)
                let active     = scene.active == index
                let hovered    = .isHoveredDocument(view.document)
                if active
                {
                    let line = metrics.fileTile_RingWidth
                    painter.fillRect(rect.x + inset, rect.y, Math.min(rect.width, 3 * inset), line, colors.arc)
                }

                if .usesCellCaptions() or not hovered and (ScenePlayer.from(view.document).film or view.document.isEdgeToEdge()) do
                    continue

                let name:    string = Path.fileName(view.path) orelse view.path
                var caption: String = name
                if relative do
                    caption = Format.toString("% · %{+f2} s", name, view.offset)
                if view.behind do
                    caption = Format.toString("% · %", caption, appStrings().scene_Behind)
                let room  = Math.max(0, rect.width - 2 * inset - ViewerWorkspace.ViewTitleHeight)
                let title = Painter.elideString(caption, font, room, .deviceScale())
                let y     = rect.y + ViewerWorkspace.ViewTitleHeight * 0.5
                painter.drawString(rect.x + inset, font.opticalLineTop(y), title, font, hovered ? colors.softText : colors.faintText)
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
                    let ink = index == scene.active ? colors.arc : (index < scene.views.count ? colors.strongLine : colors.line)
                    painter.fillRect(x, y, size, size, ink)
                }
            }
        }

        .paintDropHighlight(painter, scene)
    }
}

struct SceneDivider
{
    using wnd:      Wnd
    late workspace: *ViewerWorkspace
    dragging:       bool
}

impl SceneDivider
{
    func create(workspace: *ViewerWorkspace)->*SceneDivider
    {
        let result = Wnd.create'SceneDivider(workspace, "scope.scene.divider")
        result.workspace       = workspace
        result.backgroundStyle = .Transparent
        result.wndFlags.add(.TopMost)
        return result
    }

    mtd place(bounds: Math.Rectangle)
    {
        if bounds.isEmpty()
        {
            .stopDrag()
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
    }
}

impl IWnd for SceneDivider
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let scene = .workspace.scene()
        let point = .workspace.surfaceToLocal(evt.surfacePos)
        let hit   = scene and .isLocallyVisible() and .position.contains(point)
        switch evt.kind
        {
        case .Accept:
            evt.accepted = hit or .dragging and .mouseCapture() == me

        case .Pressed where hit and evt.button == .Left:
            .dragging = true
            .captureMouse()

        case .Released where .dragging and evt.button == .Left:
            .stopDrag()
            catch .workspace.primary.saveState()

        case .DoubleClick where hit and evt.button == .Left:
            if scene
            {
                scene.split = 0.5
                .workspace.layoutScene()
            }

        case .Move where .dragging:
            if not scene or .mouseCapture() != me
            {
                .stopDrag()
                evt.accepted = false
                return
            }

            let area  = .workspace.clientRect()
            let inset = .workspace.stripInset()
            let ratio = scene.dimensions().y == 1 ? point.x / Math.max(area.width, 1) :
                        (point.y - inset) / Math.max(area.height - inset, 1)
            scene.split = Math.clamp(ratio, 0.18, 0.82)
            .workspace.layoutScene()

        default:
            evt.accepted = false
        }
    }
}

impl ViewerWorkspace
{
    mtd createCloseFileButton()
    {
        let workspace = me
        with .closeFileButton = CaptionButton.createLeading(unwrap .surface, .WndClose, ViewerCommands.Close)
        {
            .sigPressed += func|workspace|(_) { discard workspace.activeDocument().runCommand(ViewerCommands.Close) }
            .hide()
        }
    }

    mtd refreshCloseFileButton()
    {
        if .closeFileButton == null do
            return
        let shortcut = Input.formatKeyShortcut(.Control, .W)
        let document = .activeDocument()
        let action = document.isExploring() ? appStrings().scene_CloseView : appStrings().ui_CloseFile
        .closeFileButton.toolTip = Format.toString("% (%)", action, shortcut)
        .closeFileButton.show(.scenes.count == 1 and
                              .documentCount() == 1 and
                              not document.fullScreen)
    }

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
        .restCellChrome(previous)
        document?.layoutCellCaption()
        .layoutCloseViewButtons()
        .invalidate()
    }

    private mtd restCellChrome(document: *ViewerWindow?)
    {
        if not document do
            return
        if .usesCellCaptions() and document.usesTimedViewerBar() do
            document.concealViewerBar()
        else do
            document.layoutCellCaption()
    }

    mtd isHoveredDocument(document: *ViewerWindow)->bool => .hoveredDocument == document

    mtd layoutCloseViewButtons()
    {
        let scene      = .scene()
        let count      = scene and scene.views.count > 1 ? scene.views.count : 0
        let metrics    = .themeMetrics()
        let comparison = .comparisonVisible()
        let pictures   = comparison and .comparison!.isPicture()
        while .closeViewButtons.count < count
        {
            let index     = .closeViewButtons.count
            let workspace = me
            let button    = IconButton.create(me, .theme().icon(.WndClose, metrics.chevron_Size), flags: .Overlay | .CenterContent)
            button.wndFlags.add(.TopMost)
            button.focusPolicy = .None
            button.setForm(.RoundedRectangle)
            button.sigPressed += func|workspace, index|(_) { workspace.closeView(index) }
            .closeViewButtons.add(button)
        }

        for button, index in .closeViewButtons
        {
            if not scene or
               index >= count or
               (pictures and not .comparison!.showsPictureHeader(index)) or
               (not comparison and (.usesCellCaptions() or scene.views[index].document != .hoveredDocument)) or
               not (scene.views[index].document?.isLocallyVisible() orelse false)
            {
                button.hide()
                continue
            }

            let rect = .cellRect(scene, index)
            let size = Math.min(ViewTitleHeight, Math.min(rect.width, rect.height))
            if size < metrics.chevron_Size
            {
                button.hide()
                continue
            }

            let path: string = scene.views[index].path
            let name = Path.fileName(path) orelse path
            button.toolTip = Format.toString("% · %", appStrings().scene_CloseView, name)
            let bounds = pictures ? .comparison!.pictureCloseRect(index) :
                         Math.Rectangle{rect.right() - size - metrics.wnd_CaptionButtonMargin, rect.y, size, size}
            button.setPosition(bounds, computeLayout: false)
            button.show()
        }
    }

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
                    index = i
                    break
                }
            }

            if index == Swag.U64.Max
            {
                .clearDropHighlight()
                return true
            }
        }

        if evt.kind == .Drop
        {
            .clearDropHighlight()
            if not one do
                .openScene(evt.data.files.toSlice(), .Auto)
            elif index != Swag.U64.Max do
                .replaceDocument(index, evt.data.files[0])
            else do
                .openDocument(evt.data.files[0])
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
        if evt.key == .Tab and evt.modifiers.has(.Control) and .scenes.count > 1
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

        if evt.modifiers == .Control and evt.key == .W
        {
            .closeView()
            return true
        }

        if source is EditBox or .focusedWindow() is EditBox or .activeDocument().lens.isOpen() do
            return false
        if (evt.modifiers == .Alt or evt.modifiers == .CtrlAlt) and .moveView(evt.key, evt.modifiers == .CtrlAlt) do
            return true
        if .routeComparisonKey(evt, source) or .routeSceneMediaKey(evt, source) do
            return true
        let scene = .scene()
        if scene and evt.modifiers == .None
        {
            if evt.key == .Escape and scene.maximized and not .activeDocument().searchShown or evt.key == .F and scene.views.count > 1
            {
                .toggleMaximized()
                return true
            }
        }

        return false
    }
}
