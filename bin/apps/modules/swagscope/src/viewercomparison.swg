#global internal

using Core, Gui, Pixel

enum ComparisonKind { None, Text, Binary, Structured, Picture, Media }
enum PictureComparisonMode { SideBySide, Curtain, OnionSkin, Difference, Flip }

struct SceneComparisonState
{
    options:        ComparisonOptions
    mode:           PictureComparisonMode
    selectedChange: u64
    firstRow:       u64
    separator:      f32 = 0.5
    opacity:        f32 = 0.5
    zoom:           f32 = 1
    pan:            Math.Point
    rightZoom:      f32 = 1
    rightPan:       Math.Point
    pixelAligned:   bool
    shownRight:     bool
}

struct SceneComparison
{
    using wnd:       Wnd
    late workspace:  *ViewerWorkspace
    late modeButton: *IconButton
    late zoomButton: *IconButton
    kind:            ComparisonKind
    operation:       ComparisonLoad
    text:            TextComparison
    error:           String
    paths:           [2] String
    using state:     SceneComparisonState
    drag:            bool
    pointer:         Math.Point
    diffTexture:     Texture
    diffSources:     [2] Texture
    diffFrames:      [2] u64
    diffAligned:     bool
    flipTimer:       *Timer?
    vectors:         [2] ComparedDrawing
}

impl SceneComparison
{
    const DifferenceBand = 14.0
    const RowHeight      = 24.0
    const FooterHeight   = 35.0

    func create(workspace: *ViewerWorkspace)->*SceneComparison
    {
        let result = Wnd.create'SceneComparison(workspace, "scope.scene.compare")
        result.workspace             = workspace
        result.backgroundStyle       = .Transparent
        result.modeButton            = IconButton.createQuiet(result)
        result.modeButton.sigPressed += func|comparison = result|(button) { comparison.showPictureMenu(button) }
        result.zoomButton            = IconButton.createQuiet(result)
        result.zoomButton.sigPressed += func|comparison = result|(button) { comparison.showZoomMenu(button) }
        result.hide()
        return result
    }

    mtd compare(kind: ComparisonKind, paths: [2] String, restore: const *SceneComparisonState? = null)
    {
        if not restore and .kind == kind and .paths[0] == paths[0] and .paths[1] == paths[1]
        {
            .refresh()
            return
        }

        .clearComparedDrawings()
        .kind  = kind
        .paths = paths
        if restore
        {
            .state = restore[]
        }
        else
        {
            .firstRow       = 0
            .selectedChange = 0
        }

        .text = {}
        .error.clear()
        .requestDiff()
        .refresh()
    }

    mtd requestDiff()
    {
        if .operation.started
        {
            .operation.task.cancel()
            return
        }

        if .kind == .Structured
        {
            let scene = unwrap .workspace.scene()
            let left  = assume cast(*Viewers.Binary.Panel, scene.views[0].document!.currentView)
            let right = assume cast(*Viewers.Binary.Panel, scene.views[1].document!.currentView)
            .operation.start(me, .paths, .options, .kind, [&left.doc.report, &right.doc.report])
        }
        elif .kind == .Text or .kind == .Binary
        {
            .operation.start(me, .paths, .options, .kind)
        }
    }

    mtd isPicture()->bool => .kind == .Picture or .kind == .Media

    mtd pictureView(index: u64)->*ImageView?
    {
        let scene = .workspace.scene()
        if not scene or index >= scene.views.count do
            return null
        switch scene.views[index].document?.currentView
        {
        case Viewers.Picture.Panel as image: return image.imageView
        case Viewers.Film.Panel as film:     return film.imageView
        default: return null
        }
    }

    mtd overlaysPicture()->bool => .isPicture() and .mode != .SideBySide

    mtd refresh()
    {
        let visible = .kind != .None
        .show(visible)
        if not visible
        {
            .app().renderer.removeTexture(&.diffTexture)
            return
        }

        var area = .workspace.clientRect()
        if .kind == .Media
        {
            // Leave the players' own mini-bars below the comparison and its readings.
            let scene = unwrap .workspace.scene()
            for view in scene.views
            {
                let document = unwrap view.document
                let bar      = document.viewerBar.surfaceRect()
                let top      = .workspace.surfaceToLocal({bar.x, bar.y}).y
                area.height = Math.min(area.height, Math.max(0, top - .themeMetrics().miniBar_Distance))
            }
        }

        .setPosition(area, computeLayout: false)
        .modeButton.show(.isPicture())
        .zoomButton.show(.isPicture())
        if .isPicture()
        {
            .modeButton.setQuietText(pictureModeTitle(.mode))
            .zoomButton.setQuietText(Viewer.zoomText(cast(u32, Math.round(.pictureZoom(.workspace.scene()!.active) * 100))))
            let inset = .themeMetrics().floating_Inset
            .modeButton.setPosition({area.horzCenter() - 70, area.height - FooterHeight, 140, FooterHeight}, computeLayout: false)
            .zoomButton.setPosition({area.right() - inset - 88, area.height - FooterHeight, 88, FooterHeight}, computeLayout: false)
        }

        .invalidate()
    }

    mtd setPictureMode(mode: PictureComparisonMode)
    {
        .mode = mode
        if mode == .Flip do
            .showFlippedName()
        else do
            .stopTimer(&.flipTimer)
        .refresh()
        .workspace.layoutCloseViewButtons()
        catch .workspace.primary.saveState()
    }

    mtd showFlippedName()
    {
        .stopTimer(&.flipTimer)
        .shownRight = .workspace.scene()!.active == 1
        .flipTimer = .addTimer(ViewerWindow.ViewerBarLinger)
        .workspace.layoutCloseViewButtons()
        .invalidate()
    }

    mtd step(delta: s32)
    {
        let count = .text.changes.count
        if not count do
            return
        .selectedChange = delta < 0 ? (.selectedChange + count - 1) % count : (.selectedChange + 1) % count
        .jump(.selectedChange)
    }

    mtd jump(change: u64)
    {
        if change >= .text.changes.count do
            return
        .selectedChange = change
        let row = .text.changes[change]
        .firstRow = row > 2 ? row - 2 : 0
        .invalidate()
    }

    mtd showPictureMenu(button: *IconButton)
    {
        let owner = .workspace.activeDocument()
        let menu  = MenuCtrl.createPopup(owner, owner: owner)
        menu.addItems(ComparisonCommands.PictureModes)
        discard menu.doModal(button, autoDestroy: true)
    }

    mtd showZoomMenu(button: *IconButton)
    {
        let owner = .workspace.activeDocument()
        let menu  = MenuCtrl.createPopup(owner, owner: owner)
        menu.addItems(ComparisonCommands.Zooms)
        discard menu.doModal(button, autoDestroy: true)
    }

    mtd paintText(painter: *Painter, area: Math.Rectangle)
    {
        let colors = .themeColors()
        let app    = appStrings()
        painter.fillRect(area, colors.ground)
        if not .error.isEmpty() or .operation.started
        {
            let message = .error.isEmpty() ? app.scene_LoadingComparison : .error.toString()
            painter.drawStringCenter(area.horzCenter(), area.vertCenter(), message, .theme().createDefaultFontFs(14), colors.softText)
            return
        }

        let mono   = .theme().createDefaultFontFs(.themeMetrics().defaultFixedFontSize)
        let title  = .theme().createDefaultFont(12)
        let inset  = .themeMetrics().floating_Inset
        let top    = area.y + ViewerWorkspace.ViewTitleHeight
        let bottom = area.bottom() - FooterHeight
        let band   = Math.Rectangle{area.horzCenter() - DifferenceBand / 2, top, DifferenceBand, Math.max(bottom - top, 0)}
        let left   = Math.Rectangle{area.x, top, band.x - area.x, band.height}
        let right  = Math.Rectangle{band.right(), top, area.right() - band.right(), band.height}
        let count  = .text.rows.count
        let scene  = unwrap .workspace.scene()
        for side in 2
        {
            let part         = side == 0 ? left : right
            let path: string = .paths[side]
            let name         = Path.fileName(path) orelse path
            let label        = Painter.elideString(name, title, part.width - inset, .deviceScale())
            painter.drawStringCenter(part.horzCenter(),
                                     area.y + ViewerWorkspace.ViewTitleHeight / 2,
                                     label,
                                     title,
                                     side == scene.active ? colors.text : colors.softText)
            if side == scene.active
            {
                let width = Painter.measureString(label, title).width
                painter.fillRect(part.horzCenter() - width / 2, top - 3, width, 2, colors.arc)
            }
        }

        let visible = cast(u64, Math.ceil(band.height / RowHeight))
        if .options.unified
        {
            .paintUnified(painter, Math.Rectangle{left.x, left.y, right.right() - left.x, left.height}, mono, visible)
        }
        else
        {
            painter.pushClippingRect(left)
            for row in .firstRow until Math.min(.firstRow + visible, count) do
                .paintRow(painter, left, mono, row, false)
            painter.popClippingRect()
            painter.pushClippingRect(right)
            for row in .firstRow until Math.min(.firstRow + visible, count) do
                .paintRow(painter, right, mono, row, true)
            painter.popClippingRect()
            .paintBand(painter, band, visible)
        }

        let readout = .text.changes.isEmpty() ? String.from(app.scene_Identical) :
                      Format.toString(app.scene_ChangeCount, .selectedChange + 1, .text.changes.count)
        painter.drawStringCenter(area.horzCenter(), bottom + FooterHeight / 2, readout, mono, colors.softText)
        let first = Format.toString(app.scene_LineCount, .text.left.count)
        let last  = Format.toString(app.scene_LineCount, .text.right.count)
        let y     = mono.opticalLineTop(bottom + FooterHeight / 2)
        painter.drawString(inset, y, first, mono, colors.faintText)
        painter.drawString(area.right() - inset - Painter.measureString(last, mono).width, y, last, mono, colors.faintText)
    }

    private mtd paintUnified(painter: *Painter, area: Math.Rectangle, font: *Font, visible: u64)
    {
        painter.pushClippingRect(area)
        var position = area.y
        for row in .firstRow until Math.min(.firstRow + visible, .text.rows.count)
        {
            let item = .text.rows[row]
            if item.changed and item.left != Swag.U32.Max
            {
                .paintRowAt(painter, {area.x, position, area.width, RowHeight}, font, row, false, hatch: false)
                position += RowHeight
            }

            if item.right != Swag.U32.Max
            {
                .paintRowAt(painter, {area.x, position, area.width, RowHeight}, font, row, true, hatch: false)
                position += RowHeight
            }

            if position >= area.bottom() do
                break
        }

        painter.popClippingRect()
    }

    private mtd paintRow(painter: *Painter, column: Math.Rectangle, font: *Font, index: u64, right: bool)
    {
        let area = Math.Rectangle{column.x, column.y + cast(f32, index - .firstRow) * RowHeight, column.width, RowHeight}
        .paintRowAt(painter, area, font, index, right, hatch: true)
    }

    private mtd paintRowAt(painter: *Painter, area: Math.Rectangle, font: *Font, index: u64, right, hatch: bool)
    {
        let row    = .text.rows[index]
        let line   = right ? row.right : row.left
        let colors = .themeColors()
        let ink    = right ? colors.added : colors.removed
        if line == Swag.U32.Max
        {
            if hatch
            {
                painter.pushClippingRect(area)
                for stripe in cast(u64, (area.width + area.height) / 8)
                {
                    let x = area.x + cast(f32, stripe) * 8
                    painter.drawLine(x, area.y, x - area.height, area.bottom(), colors.line)
                }

                painter.popClippingRect()
            }

            return
        }

        if row.changed do
            painter.fillRect(area, right ? colors.addedBk : colors.removedBk)
        let y           = font.opticalLineTop(area.vertCenter())
        let number      = .kind == .Binary ? Format.toString("%{X08}", cast(u64, line) * 16) : Format.toString("%", line + 1)
        let numberWidth = .kind == .Binary ? 91.0 : 62.0
        painter.drawString(area.x + numberWidth - 20 - Painter.measureString(number, font).width, y, number, font, colors.faintText)
        if row.changed do
            painter.drawString(area.x + numberWidth - 12, y, right ? "+" : "−", font, ink)
        let lineText: string = right ? .text.right[line].text : .text.left[line].text
        let x = area.x + numberWidth + 4
        if row.changed and row.left != Swag.U32.Max and row.right != Swag.U32.Max
        {
            let other: string = right ? .text.left[row.left].text : .text.right[row.right].text
            let span          = changedCharacters(lineText, other)
            let before        = Painter.measureString(lineText[until span.start], font).width
            let width         = Painter.measureString(lineText[span.start until span.end], font).width
            painter.fillRect(x + before, area.y + 3, width, area.height - 6, ink.withAlphaF32(0.30))
        }

        painter.drawString(x, y, lineText, font, colors.text)
    }

    private mtd paintBand(painter: *Painter, area: Math.Rectangle, visible: u64)
    {
        let colors = .themeColors()
        painter.fillRect(area, colors.raised)
        if .text.rows.isEmpty() do
            return
        let scale = area.height / cast(f32, .text.rows.count)
        for row, index in .text.changes
        {
            let y = area.y + scale * cast(f32, row)
            painter.fillRect(area.x + 2, y, 4, 2, colors.removed)
            painter.fillRect(area.x + 8, y, 4, 2, colors.added)
            if index == .selectedChange do
                painter.fillRect(area.x, y, area.width, 2, colors.arc)
        }

        let y      = area.y + cast(f32, .firstRow) * scale
        let height = Math.clamp(cast(f32, visible) * scale, 3, Math.max(area.bottom() - y, 3))
        painter.drawRect({area.x + 0.5, y + 0.5, area.width - 1, height - 1}, colors.softText)
    }
}

impl IWnd for SceneComparison
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .operation.task.cancel()
        .operation.wait()
        .clearComparedDrawings()
        .app().renderer.removeTexture(&.diffTexture)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .flipTimer
        {
            evt.accepted = false
            return
        }

        .stopTimer(&.flipTimer)
        .workspace.layoutCloseViewButtons()
        .invalidate()
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .operation.claim(evt)
        {
            evt.accepted = false
            return
        }

        let valid = .operation.paths[0] == .paths[0] and
                    .operation.paths[1] == .paths[1] and
                    .operation.options == .options and
                    .operation.kind == .kind
        .operation.wait()
        if not valid
        {
            .requestDiff()
            return
        }

        .text           = #move .operation.text
        .error          = #move .operation.error
        .firstRow       = Math.min(.firstRow, .text.rows.isEmpty() ? 0 : .text.rows.count - 1)
        .selectedChange = Math.min(.selectedChange, .text.changes.isEmpty() ? 0 : .text.changes.count - 1)
        .invalidate()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect  = .clientRect()
        let strip = .stripInset()
        let area  = Math.Rectangle{rect.x, rect.y + strip, rect.width, Math.max(rect.height - strip, 0)}
        if .isPicture() do
            .paintPictures(evt.paintContext.painter, area)
        else do
            .paintText(evt.paintContext.painter, area)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let point = .surfaceToLocal(evt.surfacePos)
        let body  = .clientRect()
        if .isPicture()
        {
            .picturePointer(evt, point)
            return
        }

        switch evt.kind
        {
        case .Accept:
            evt.accepted = point.y >= .stripInset()

        case .Wheel:
            let step    = evt.delta.y > 0 ? -3 : 3
            let maximum = Math.max(cast(s64, .text.rows.count) - 1, 0)
            .firstRow = cast(u64, Math.clamp(cast(s64, .firstRow) + step, 0, maximum))
            .invalidate()

        case .Pressed where evt.button == .Left:
            let y      = .stripInset() + ViewerWorkspace.ViewTitleHeight
            let height = Math.max(body.height - FooterHeight - y, 1)
            if not .options.unified and
               Math.abs(point.x - body.horzCenter()) <= DifferenceBand / 2 and
               not .text.changes.isEmpty()
            {
                let row = Math.clamp((point.y - y) / height, 0, 1) * cast(f32, .text.rows.count)
                var nearest: u64
                for candidate, index in .text.changes
                {
                    if Math.abs(cast(f32, candidate) - row) < Math.abs(cast(f32, .text.changes[nearest]) - row) do
                        nearest = index
                }

                .jump(nearest)
            }
            else
            {
                .workspace.selectView(point.x < body.horzCenter() ? 0 : 1)
            }

        default:
            evt.accepted = false
        }
    }
}

private func changedCharacters(first, second: string)->{start, end: u64}
{
    var start: u64
    var end   = first.count
    var other = second.count
    while start < end and start < other and first[start] == second[start] do
        start += 1
    while start and start < end and (first[start] & 0xC0) == 0x80 do
        start -= 1
    while end > start and other > start and first[end - 1] == second[other - 1]
    {
        end   -= 1
        other -= 1
    }

    while end < first.count and (first[end] & 0xC0) == 0x80 do
        end += 1
    return {start, end}
}

impl ViewerWorkspace
{
    mtd comparisonVisible()->bool => .comparison and .comparison.isLocallyVisible()

    mtd swapSceneViews(first, second: u64)
    {
        let scene = unwrap .scene()
        scene.swapViews(first, second)
        if scene.views.count != 2 or scene.linked and scene.links.framing do
            return
        if .comparisonScene == scene and .comparison
        {
            swap(&.comparison.zoom, &.comparison.rightZoom)
            swap(&.comparison.pan, &.comparison.rightPan)
        }
        else
        {
            swap(&scene.comparisonState.zoom, &scene.comparisonState.rightZoom)
            swap(&scene.comparisonState.pan, &scene.comparisonState.rightPan)
        }
    }

    mtd toggleComparison()
    {
        let scene = .scene()
        if not scene or scene.views.count != 2 do
            return
        scene.compared  = not scene.compared
        scene.linked    = scene.compared
        scene.layout    = .SideBySide
        scene.maximized = false
        .layoutScene()
        catch .primary.saveState()
    }

    mtd refreshComparison()
    {
        defer .layoutCloseViewButtons()
        let scene = .scene()
        if not scene or not scene.compared or scene.views.count != 2 or scene.maximized
        {
            .comparison?.hide(keepActivities: true)
            return
        }

        if not .comparison do
            .comparison = SceneComparison.create(me)

        var kind       = ComparisonKind.Text
        var paths: [2] String
        var picture    = true
        var media      = true
        var structured = true
        for &view, index in scene.views
        {
            paths[index] = view.path
            let current = view.document?.currentView
            if not current
            {
                .comparison?.hide(keepActivities: true)
                return
            }

            picture    = picture and current is Viewers.Picture.Panel
            media      = media and current is Viewers.Film.Panel
            structured = structured and current is Viewers.Binary.Panel
            if current is Viewers.Hex.Panel or current is Viewers.Binary.Panel do
                kind = .Binary
        }

        if picture
        {
            kind = .Picture
        }
        elif media
        {
            kind = .Media
        }
        elif structured
        {
            for view in scene.views
            {
                let panel = assume cast(*Viewers.Binary.Panel, view.document!.currentView)
                if not panel.loadPublished
                {
                    .comparison?.hide(keepActivities: true)
                    return
                }

                structured = structured and panel.doc.kind != .Unknown
            }

            if structured do
                kind = .Structured
        }
        elif kind != .Binary
        {
            for view in scene.views
            {
                let document = view.document
                if not document or document.activeChoiceIndex >= document.choices.count do
                    return
                let key = document.choices[document.activeChoiceIndex].key
                if key != "text" and key != "code" and key != "markdown"
                {
                    .comparison?.hide(keepActivities: true)
                    return
                }
            }
        }

        let restore = .comparisonScene != scene
        .comparisonScene = scene
        .comparison.compare(kind, paths, restore ? &scene.comparisonState : null)
        .comparison.bringToFront()
    }
}
