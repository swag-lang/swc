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
            let close = Math.Rectangle{item.right(), item.y, Gap * 0.5 + 1, item.height}
            if evt.button == .Middle or evt.button == .Left and .showsClose(index) and close.contains(point) do
                .workspace.closeScene(index)
            elif evt.button == .Left do
                .workspace.selectScene(index)

        default:
            evt.accepted = false
        }
    }
}

struct SceneOverlay
{
    using wnd:      Wnd
    late workspace: *ViewerWorkspace
}

impl SceneOverlay
{
    func create(workspace: *ViewerWorkspace)->*SceneOverlay
    {
        let result = Wnd.create'SceneOverlay(workspace, "scope.scene.overlay")
        result.workspace       = workspace
        result.backgroundStyle = .Transparent
        // Only the divider takes pointer input. The overlay paints over the document windows.
        result.disable()
        return result
    }

    mtd divider()->Math.Rectangle
    {
        let scene = .workspace.scene()
        if not scene or
           scene.views.count != 2 or
           scene.maximized or
           scene.layout == .Single or
           scene.compared do
            return {}
        let grid  = scene.dimensions()
        let first = .workspace.viewRect(scene, 0)
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
        if .workspace.comparisonVisible()
        {
            let half   = body.width * 0.5
            let height = Math.max(0, body.bottom() - SceneComparison.FooterHeight - top)
            return {body.x + cast(f32, index) * half, top, half, height}
        }

        var rect  = .workspace.viewRect(scene, index)
        rect.intersect({0, top, body.width, Math.max(0, body.bottom() - top)})
        return rect
    }

    mtd dropRect(scene: const *ViewerScene, index: u64)->Math.Rectangle
    {
        var rect = .cellRect(scene, index)
        let compare = .workspace.comparison
        if not compare or not compare.isLocallyVisible() or not compare.isPicture() or compare.mode != .Curtain do
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
        let index = .workspace.dropView
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
}

impl IWnd for SceneOverlay
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let scene = .workspace.scene()
        if not scene do
            return

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let font    = .theme().createDefaultFont(12)
        let strip   = .stripInset()
        if .workspace.mediaChromeVisible() and strip > 0
        {
            let shade = colors.floating_Shadow
            let veil  = Brush.createLinearGradient(0, 0, 0, strip + 16, shade.withAlphaF32(0.75), shade.withAlphaF32(0))
            painter.fillRect(0, 0, .clientRect().width, strip + 16, veil)
        }

        if scene.views.count > 1 and not .workspace.comparisonVisible()
        {
            let divider = .divider()
            if divider.width > 0 and not .workspace.isMediaScene()
            {
                let vertical = scene.dimensions().y == 1
                let line     = vertical ? Math.Rectangle{divider.x + 3, divider.y, 1, divider.height} :
                               Math.Rectangle{divider.x, divider.y + 3, divider.width, 1}
                painter.fillRect(line, colors.line)
            }

            for view, index in scene.views where view.document and view.document.isLocallyVisible()
            {
                let rect         = .workspace.viewRect(scene, index)
                let name: string = Path.fileName(view.path) orelse view.path
                let controls     = 2 * (ViewerWorkspace.ViewTitleHeight + .themeMetrics().wnd_CaptionButtonMargin)
                let text         = Painter.elideString(name, font, Math.max(rect.width - controls, 0), .deviceScale())
                let active       = scene.active == index
                if view.document.isEdgeToEdge()
                {
                    .workspace.paintCloseViewGround(painter, index)
                    if .workspace.mediaChromeVisible() do
                        .workspace.paintMediaCaption(painter, rect, view, text, active)
                    elif index == .workspace.audibleIndex(scene) do
                        .theme().icon(.Volume, 16).paint(painter, rect.x + 12, rect.y + 12, colors.softText)
                    continue
                }

                let y = rect.y + ViewerWorkspace.ViewTitleHeight * 0.5
                painter.drawStringCenter(rect.horzCenter(), y, text, font, active ? colors.text : colors.softText)
                if active
                {
                    let width = Painter.measureString(text, font).width
                    painter.fillRect(rect.horzCenter() - width * 0.5, rect.y + ViewerWorkspace.ViewTitleHeight - 3, width, 2, colors.arc)
                }
            }

            if scene.maximized
            {
                let area   = .clientRect()
                let size   = 5.0
                let grid   = scene.dimensions(useMaximized: false)
                let cols   = cast(u64, grid.x)
                let left   = area.right() - 20 - grid.x * (size + 2)
                let bottom = area.bottom() - 20 - grid.y * (size + 2) -
                             (.workspace.mediaChromeVisible() ? Viewers.Film.BottomHeight : 0)
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
            let inset = .workspace.overlay.stripInset()
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
        .closeFileButton.toolTip = Format.toString("% (%)", appStrings().ui_CloseFile, shortcut)
        .closeFileButton.show(.scenes.count == 1 and .documentCount() == 1 and not document.isExploring() and not document.fullScreen)
    }

    mtd layoutCloseViewButtons()
    {
        if .overlay == null do
            return
        let scene = .scene()
        let count = scene and scene.views.count > 1 and not .compactMedia ? scene.views.count : 0
        let metrics = .themeMetrics()
        let pictures = .comparisonVisible() and .comparison!.isPicture()
        while .closeViewButtons.count < count
        {
            let index     = .closeViewButtons.count
            let workspace = me
            let button    = IconButton.create(me, .theme().icon(.WndClose, metrics.wnd_CaptionButtonGlyph), flags: .Overlay | .CenterContent)
            button.wndFlags.add(.TopMost)
            button.setForm(.RoundedRectangle)
            button.sigPressed += func|workspace, index|(_) { workspace.closeView(index) }
            .closeViewButtons.add(button)
        }

        for button, index in .closeViewButtons
        {
            if not scene or index >= count or not (scene.views[index].document?.isLocallyVisible() orelse false)
            {
                button.hide()
                continue
            }

            let rect = .overlay.cellRect(scene, index)
            let size = Math.min(ViewTitleHeight, Math.min(rect.width, rect.height))
            if size < metrics.wnd_CaptionButtonGlyph
            {
                button.hide()
                continue
            }

            let path: string = scene.views[index].path
            let name = Path.fileName(path) orelse path
            button.toolTip = Format.toString("% · %", appStrings().ui_CloseFile, name)
            let bounds = pictures ? .comparison!.pictureCloseRect(index) :
                         Math.Rectangle{rect.right() - size - metrics.wnd_CaptionButtonMargin, rect.y, size, size}
            button.setPosition(bounds, computeLayout: false)
            button.show()
        }
    }

    mtd paintCloseViewGround(painter: *Painter, index: u64)
    {
        if index >= .closeViewButtons.count do
            return
        let button = .closeViewButtons[index]
        if not button.isLocallyVisible() do
            return
        let corner = .themeMetrics().corner_Chip
        painter.fillRoundRect(button.position, corner, corner, .themeColors().raised)
    }

    mtd showMaximizedHint(show: bool)
    {
        if not show
        {
            .maxHint?.hide()
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
            .overlay.invalidate()
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
            let point = .overlay.surfaceToLocal(evt.surfacePos)
            for view, i in scene.views where (view.document?.isLocallyVisible() orelse false)
            {
                let rect = .overlay.dropRect(scene, i)
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
            .overlay.bringToFront()
            .overlay.invalidate()
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

        if (evt.modifiers == .Alt or evt.modifiers == .CtrlAlt) and .moveView(evt.key, evt.modifiers == .CtrlAlt) do
            return true
        if .routeComparisonKey(evt, source) or .routeSceneMediaKey(evt, source) do
            return true
        let scene = .scene()
        if scene and
           evt.modifiers == .None and
           not (source is EditBox) and
           not .activeDocument().lens.isOpen()
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
