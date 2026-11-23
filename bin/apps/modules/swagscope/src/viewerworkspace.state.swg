#global internal

using Core, Gui, Pixel

struct SavedSceneView
{
    path:      String
    reading:   ViewerReadingState
    readState: bool
    offset:    f64
    playMode:  Viewer.PlayMode
}

struct SavedScene
{
    views:      Array'SavedSceneView
    layout:     SceneLayout
    active:     u64
    recent:     u64
    split:      f32
    maximized:  bool
    compared:   bool
    linked:     bool
    links:      SceneLinks
    savedEndMode: bool
    comparison: SceneComparisonState
}

impl ViewerWorkspace
{
    mtd storeComparisonState()
    {
        let scene = .scene()
        if scene and scene == .comparisonScene and .comparison do
            scene.comparisonState = .comparison.state
    }

    mtd serializeScenes(serializer: *Serialization.Serializer)
    {
        if serializer.isReading()
        {
            catch serializer.serialize("Scope.Scenes", &.restored)
            catch serializer.serialize("Scope.ActiveScene", &.restoredTab)
            return
        }

        .storeComparisonState()
        var saved:    Array'SavedScene
        var selected: u64
        for sceneValue, index in .scenes
        {
            let scene = unwrap sceneValue
            var record: SavedScene
            record.layout       = scene.layout
            record.recent       = scene.recent
            record.split        = scene.split
            record.maximized    = scene.maximized
            record.compared     = scene.compared
            record.linked       = scene.linked
            record.links        = scene.links
            record.savedEndMode = true
            record.links.leader = Swag.U64.Max
            record.links.solo   = Swag.U64.Max
            record.comparison   = scene.comparisonState
            for &view, viewIndex in scene.views
            {
                let owner = view.document orelse .primary
                if not owner.privacy.mayRemember(view.path) do
                    continue
                if viewIndex == scene.active do
                    record.active = record.views.count
                if viewIndex == scene.links.leader do
                    record.links.leader = record.views.count
                if viewIndex == scene.links.solo do
                    record.links.solo = record.views.count
                .captureView(view)
                record.views.add({path: view.path, reading: view.reading, readState: view.readState, offset: view.offset, playMode: view.playMode})
            }

            if record.views.isEmpty() do
                continue
            if index == .active do
                selected = saved.count
            saved.add(#move record)
        }

        catch serializer.serialize("Scope.Scenes", &saved)
        catch serializer.serialize("Scope.ActiveScene", &selected)
    }

    mtd restoreScenes(resume = true)
    {
        if not .scenes.isEmpty() do
            return
        defer .restored.clear()
        for &record in .restored
        {
            if .scenes.count >= MaxScenes do
                break
            var scene: ViewerScene
            if cast(u32, record.layout) <= cast(u32, SceneLayout.Auto) do
                scene.layout = record.layout
            scene.split = Math.clamp(record.split, 0.18, 0.82)
            for &view in record.views
            {
                if scene.views.count >= MaxViews do
                    break
                if not view.path.isEmpty() and .primary.privacy.mayRemember(view.path) do
                    scene.views.add({path: #move view.path, reading: #move view.reading, readState: view.readState, offset: view.offset, playMode: view.playMode})
            }

            if scene.views.isEmpty() do
                continue
            scene.active          = Math.min(record.active, scene.views.count - 1)
            scene.maximized       = record.maximized and scene.views.count > 1
            if scene.layout == .Single and scene.views.count > 1
            {
                scene.layout    = .Auto
                scene.maximized = true
            }
            scene.recent          = record.recent
            scene.compared        = record.compared and scene.views.count == 2
            scene.linked          = record.linked and scene.views.count > 1
            scene.links           = record.links
            // Older sessions stored Stop with Shortest as their default.
            if not record.savedEndMode and scene.links.end == .Shortest do
                scene.links.end = .Independent
            scene.comparisonState = record.comparison
            .activation           = Math.max(.activation, scene.recent)
            .scenes.addNew()[]    = #move scene
        }

        if .scenes.isEmpty() do
            return
        .active = Math.min(.restoredTab, .scenes.count - 1)
        if resume do
            .resumeScene(false)
    }
}

struct SceneSwitcherList
{
    using wnd:      Wnd
    late workspace: *ViewerWorkspace
}

impl IWnd for SceneSwitcherList
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let workspace = .workspace
        let painter   = evt.paintContext.painter
        let area      = .clientRect()
        let colors    = .themeColors()
        let heading   = .theme().createDefaultFont(11)
        let title     = .theme().createDefaultFont(14)
        let detail    = .theme().createDefaultFont(12)
        let text      = appStrings()
        painter.drawString(14, 8, Format.toString(text.scene_Scenes, workspace.scenes.count), heading, colors.faintText)
        let visible = .rows()
        let offset  = .firstRow()
        for slot in visible
        {
            let row   = slot + offset
            let index = workspace.switchOrder[row]
            let scene = unwrap workspace.scenes[index]
            let rect  = Math.Rectangle{0, 28 + cast(f32, slot) * 56, area.width, 54}
            if row == workspace.switchCursor do
                painter.fillRoundRect(rect, 8, 8, colors.selection)
            let preview = Math.Rectangle{12, rect.y + 7, 64, 40}
            painter.fillRoundRect(preview, 5, 5, colors.raised)
            let size = scene.dimensions()
            if scene.preview.isValid()
            {
                painter.drawTexture(preview, scene.preview)
            }
            elif scene.views.count == 1
            {
                let icon = .theme().fileGlyph(scene.views[0].path, false, 24)
                icon.paint(painter, preview.horzCenter() - 12, preview.vertCenter() - 12, colors.softText)
            }
            else
            {
                let cols   = cast(u64, size.x)
                let width  = preview.width / size.x
                let height = preview.height / size.y
                for view, cell in scene.views
                {
                    let x = preview.x + cast(f32, cell % cols) * width
                    let y = preview.y + cast(f32, cell / cols) * height
                    if y + height <= preview.bottom()
                    {
                        let glyph = .theme().fileGlyph(view.path, false)
                        painter.fillRect(x + 1, y + 1, width - 2, height - 2, glyph.color.withAlphaF32(0.23))
                    }
                }
            }

            let name = scene.name(.theme())
            painter.drawString(90, rect.y + 10, Painter.elideString(name, title, rect.width - 104, .deviceScale()), title, colors.text)
            let description = scene.views.count == 1 ? Path.lowercaseExtension(scene.views[0].path) :
                              String.from(sceneLayoutTitle(scene.layout))
            let caption = index == workspace.active ? Format.toString("% · %", description, text.scene_Current) : description
            painter.drawString(90, rect.y + 28, Painter.elideString(caption, detail, rect.width - 104, .deviceScale()), detail, colors.faintText)
        }

        painter.fillRect(0, area.height - 35, area.width, 1, colors.line)
        painter.drawString(12, area.height - 25, Painter.elideString(text.scene_SwitchHint, detail, area.width - 24, .deviceScale()), detail, colors.faintText)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let point = .surfaceToLocal(evt.surfacePos)
        let row   = cast(u64, Math.max(point.y - 28, 0) / 56)
        if evt.kind == .Pressed and evt.button == .Left and point.y >= 28 and row < .rows()
        {
            .workspace.switchCursor = .firstRow() + row
            .workspace.closeSwitcher(choose: true)
            return
        }

        evt.accepted = evt.kind == .Accept
    }
}

impl SceneSwitcherList
{
    mtd rows()->u64 => Math.min(.workspace.switchOrder.count, cast(u64, Math.max(.clientRect().height - 63, 0) / 56))

    mtd firstRow()->u64
    {
        let rows   = .rows()
        let cursor = .workspace.switchCursor
        return cursor < rows ? 0 : cursor - rows + 1
    }
}

impl ViewerWorkspace
{
    mtd captureScenePreview()
    {
        let scene   = .scene()
        let surface = .surface
        if not scene or
           scene.recent != .paintedScene or
           not surface or
           not surface.rt.colorBuffer.isValid() or
           .switcher or
           .activeDocument().lens.isOpen() do
            return

        let rect   = .surfaceRect()
        let scale  = .deviceScale()
        let room   = surface.rt.colorBuffer
        let x      = Math.clamp(cast(s32, rect.x * scale), 0, room.width - 1)
        let y      = Math.clamp(cast(s32, (rect.y + .stripInset()) * scale), 0, room.height - 1)
        let width  = Math.min(cast(s32, rect.width * scale), room.width - x)
        let height = Math.min(cast(s32, (rect.height - .stripInset()) * scale), room.height - y)
        if width < 64 or height < 40 do
            return

        let cropWidth  = Math.min(width, height * 64 / 40)
        let cropHeight = Math.min(height, width * 40 / 64)
        let renderer   = .app().renderer
        var image      = surface.captureFrame(x + (width - cropWidth) / 2, y + (height - cropHeight) / 2, cropWidth, cropHeight)
        if image.pixels.isEmpty() do
            return
        image.resize(64, 40, .Bilinear)
        renderer.removeTexture(&scene.preview)
        scene.preview = renderer.addImage(image)
    }

    mtd cycleSwitcher(backward: bool)
    {
        if .scenes.count < 2 do
            return
        if not .switcher
        {
            .captureScenePreview()
            .switchOrder.clear()
            for index in .scenes.count do
                .switchOrder.add(index)
            let workspace = me
            .switchOrder.sort(func|workspace|(first, second)->s32
            {
                let a = workspace.scenes[first]!.recent
                let b = workspace.scenes[second]!.recent
                return a == b ? 0 : (a > b ? -1 : 1)
            })
            .switchCursor = 0

            let area     = .clientRect()
            let width    = Math.min(460, area.width - 32)
            let rows     = Math.min(.switchOrder.count, cast(u64, Math.max(area.height - 150, 112.0) / 56))
            let height   = 79 + cast(f32, rows) * 56
            let backdrop = Wnd.create'Wnd(me, area, "scope.scene.switcher.backdrop")
            backdrop.backgroundStyle = .Transparent
            backdrop.hookOnEvent     = func|workspace|(wnd, evt)
            {
                if evt is MouseEvent as mouse where mouse.target == wnd
                {
                    if mouse.kind == .Pressed do
                        workspace.closeSwitcher(choose: false)
                    mouse.accepted = mouse.kind == .Accept or mouse.kind == .Pressed
                    return mouse.accepted
                }

                return false
            }

            backdrop.wndFlags.add(.TopMost)
            backdrop.bringToFront()
            .switchBackdrop = backdrop
            .switcher       = FloatingPanel.create(backdrop,
                                                   {area.horzCenter() - width / 2, Math.max(.stripInset() + 8, area.height * 0.19), width, height},
                                                   "scope.scene.switcher")
            let metrics = .themeMetrics()
            backdrop.backdrop = {algorithm: .Gaussian, radius: metrics.lens_BlurRadius * 3,
                                 saturation: metrics.lens_Saturation,
                                 tint: .themeColors().floating_Shadow.withAlphaF32(metrics.lens_TintOpacity)}
            let list = Wnd.create'SceneSwitcherList(.switcher)
            list.workspace       = me
            list.backgroundStyle = .Transparent
            list.dockStyle       = .Center
            .switcher.applyLayout()
            discard .app().animator.arrive(.switcher)
        }

        let count = .switchOrder.count
        .switchCursor = backward ? (.switchCursor + count - 1) % count : (.switchCursor + 1) % count
        .switcher.invalidate()
    }

    mtd closeSwitcher(choose: bool)
    {
        if not .switcher do
            return
        let index = .switchOrder[.switchCursor]
        .switchBackdrop?.destroy()
        .switchBackdrop = null
        .switcher       = null
        if choose do
            .selectScene(index, capturePreview: false)
    }
}
