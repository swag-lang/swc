#global internal

using Core, Gui, Pixel

enum SceneDropTarget { Replace, Left, Right, Below, NewTab }
const SceneDropTargets = [SceneDropTarget.Replace, .Left, .Right, .Below, .NewTab]

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
        if not .isLocallyVisible() do
            return
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
        if width > room.width
        {
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

        let active = .items[selected]
        let next   = Math.Rectangle{active.x, room.height - 12, active.width, 2}
        if .underline != next
        {
            .previous     = .underline.width > 0 ? .underline : next
            .underline    = next
            .slideStarted = Time.monotonicMicroseconds()
            if not .slideTimer and not .app().isReducedMotion() do
                .slideTimer = .addTimer(16'ms)
        }

        .invalidate()
    }

    mtd hit(position: Math.Point)->u64
    {
        for rect, index in .items
        {
            let target = Math.Rectangle{rect.x - Gap * 0.5, 0, rect.width + Gap, rect.height}
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
            if index == .hovered do
                .theme().icon(.WndClose, CloseSize).paint(painter, item.right() + 1, item.vertCenter() - CloseSize * 0.5, colors.softText)
        }

        var mark = .underline
        if .slideTimer
        {
            let seconds   = cast(f32, Time.monotonicMicroseconds() - .slideStarted) / 1_000_000
            let remaining = 1 - Math.clamp(seconds / .themeMetrics().motion_PageSeconds, 0, 1)
            let blend     = remaining * remaining
            mark.x     += (.previous.x - mark.x) * blend
            mark.width += (.previous.width - mark.width) * blend
        }

        painter.fillRect(mark, colors.arc)
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        let elapsed = cast(f32, Time.monotonicMicroseconds() - .slideStarted) / 1_000_000
        if elapsed >= .themeMetrics().motion_PageSeconds do
            .stopTimer(&.slideTimer)
        .invalidate()
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
            if evt.button == .Middle or evt.button == .Left and index == .hovered and point.x >= .items[index].right() do
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

    mtd dropRect(target: SceneDropTarget)->Math.Rectangle
    {
        let scene  = unwrap .workspace.scene()
        let area   = .workspace.viewRect(scene, scene.active)
        let width  = Math.min(126, area.width * 0.29)
        let height = Math.min(48, area.height * 0.18)
        let center = area.horzCenter()
        let middle = area.vertCenter()
        switch target
        {
        case .Left:   return {area.x + 12, middle - height / 2, width, height}
        case .Right:  return {area.right() - width - 12, middle - height / 2, width, height}
        case .Below:  return {center - width / 2, area.bottom() - height - 12, width, height}
        case .NewTab: return {.clientRect().horzCenter() - width / 2, 8, width, 34}
        default:      return {center - width / 2, middle - height / 2, width, height}
        }
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
        let body    = Math.Rectangle{0, strip, .clientRect().width, .clientRect().height - strip}
        if .workspace.mediaChromeVisible() and strip > 0
        {
            let shade = colors.floating_Shadow
            let veil  = Brush.createLinearGradient(0, 0, 0, strip + 16, shade.withAlphaF32(0.75), shade.withAlphaF32(0))
            painter.fillRect(0, 0, body.width, strip + 16, veil)
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
                let text         = Painter.elideString(name, font, Math.max(rect.width - 24, 0), .deviceScale())
                let active       = scene.active == index
                if view.document.isEdgeToEdge()
                {
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

        if .workspace.dragging
        {
            painter.fillRect(body, colors.floating_Shadow.withAlphaF32(0.48))
            let labels = [appStrings().scene_Replace, appStrings().scene_Left, appStrings().scene_Right,
                          appStrings().scene_Below, appStrings().scene_NewTab]
            for index in labels.count
            {
                let target = SceneDropTargets[index]
                let rect   = .dropRect(target)
                let chosen = target == .workspace.dropTarget
                let radius = .themeMetrics().corner_Control
                painter.fillRoundRect(rect, radius, radius, chosen ? colors.selection : colors.raised)
                painter.drawRoundRect(rect, radius, radius, chosen ? colors.arc : colors.line, chosen ? 2 : 1)
                painter.drawStringCenter(rect.horzCenter(), rect.vertCenter(), labels[index], font, colors.text)
            }
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let divider = .divider()
        let point   = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Accept:
            evt.accepted = divider.width > 0 and divider.contains(point)

        case .Pressed where evt.button == .Left:
            .workspace.splitDrag = true
            .captureMouse()

        case .Released where .workspace.splitDrag:
            .workspace.splitDrag = false
            .releaseMouse()
            catch .workspace.primary.saveState()

        case .DoubleClick where evt.button == .Left:
            let scene = unwrap .workspace.scene()
            scene.split = 0.5
            .workspace.layoutScene()

        case .Move where .workspace.splitDrag:
            let scene = unwrap .workspace.scene()
            let area  = .clientRect()
            let ratio = scene.dimensions().y == 1 ? point.x / Math.max(area.width, 1) :
                        (point.y - .stripInset()) / Math.max(area.height - .stripInset(), 1)
            scene.split = Math.clamp(ratio, 0.18, 0.82)
            .workspace.layoutScene()

        default:
            evt.accepted = false
        }
    }
}

impl ViewerWorkspace
{
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

    mtd dropFiles(evt: *DragDropEvent)->bool
    {
        if evt.kind == .Leave
        {
            .dragging = false
            .primary.dropHighlight.hide()
            .overlay.invalidate()
            return true
        }

        if not evt.data.hasFiles() or evt.data.files.count > MaxViews do
            return false
        let effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
        if effect == .None do
            return false

        let scene = .scene()
        if scene
        {
            let point = .surfaceToLocal(evt.surfacePos)
            .dragging   = true
            .dropTarget = .Replace
            for i in 5
            {
                let target = SceneDropTargets[i]
                if .overlay.dropRect(target).contains(point)
                {
                    .dropTarget = target
                    break
                }
            }

            .overlay.invalidate()
        }
        else
        {
            .primary.dropHighlight.showTarget(false)
        }

        if evt.kind == .Drop
        {
            .dragging = false
            .overlay.invalidate()
            .primary.dropHighlight.hide()
            if evt.data.files.count > 1 do
                .openScene(evt.data.files.toSlice(), .Auto)
            elif scene do
                .insertDocument(evt.data.files[0], .dropTarget)
            else do
                .openDocument(evt.data.files[0])
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

        if evt.key == .Escape and .switcher
        {
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
