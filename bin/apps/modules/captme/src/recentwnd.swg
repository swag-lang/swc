const MaxRecent = 15

const RecentPadding = 8.0

struct RecentItem
{
    file:               String
    linked:             String
    linkedUpToDate:     bool
    preview:            Texture
    rect:               Math.Rectangle
    zoom:               f32
}

struct RecentInfos
{
    hot:                bool
    selected:           bool
    linkedUpToDate:     bool
    linked:             String
}

struct RecentView
{
    using wnd:     Wnd

    main:          *MainWnd
    recentWnd:     *RecentWnd
    items:         ArrayPtr'RecentItem
    selected:      u64 = Swag.U64.Max
    hotItem:       u64 = Swag.U64.Max
}

impl RecentView
{
    mtd select(idx: u64, force = false)
    {
        if .selected == idx and !force do
            return

        if idx >= .items.count
        {
            .selected = Swag.U64.Max
            return
        }

        let view = .main.editWnd.editView

        // Save current zoom
        if .selected < .items.count do
            .items[.selected].zoom = view.zoom

        // Select new recent item
        .selected = idx
        let item    = .items[idx]
        let capture = catch Capture.load(item.file)
        if capture
        {
            let previousCapture = .main.getCapture()
            if previousCapture do
                .main.saveCapture(assume previousCapture)
            view.setCapture(capture)
            if item.zoom == 0 do
                view.zoomToFit(false)
            else do
                view.setZoom(item.zoom)
            view.main.freezeSelection(false)
            .invalidate()
        }
    }
}

impl IWnd for RecentView
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .MouseWheel do
            evt.accepted = false

        var pos = .surfaceToLocal(evt.surfacePos)
        pos += .recentWnd.getScrollPos()

        // Hit test
        var ht = Swag.U64.Max
        for i, idx in .items
        {
            if i.rect.contains(pos)
            {
                ht = idx
                break
            }
        }

        if ht != .hotItem
        {
            .invalidate()
            .hotItem = ht
        }

        if evt.kind == .MousePressed and .hotItem != Swag.U64.Max
        {
            if evt.button == .Left or evt.button == .Right
            {
                .select(.hotItem)
                if evt.button == .Right
                {
                    with let menu = MenuCtrl.createPopup(me)
                    {
                        .addItem(ActionFile.UpdateLinkedImage)
                        .addSeparator()
                        .addItem(ActionFile.DupCapture)
                        .addItem(ActionFile.DeleteCapture)
                        .addSeparator()
                        .addItem(ActionCopyPaste.CopyAsImage)
                        .addSeparator()
                        .addItem(ActionFile.CaptureFileLocation)
                        .addItem(ActionFile.LinkedFileLocation)
                        .addSeparator()
                        .addItem(ActionFile.FileDetails)
                    }

                    discard menu.doModal(evt.surfacePos, autoDestroy: true)
                }
            }
        }
    }

    func paintRecent(parent: *Wnd, painter: *Painter, texture: Texture, rect: Math.Rectangle, infos: RecentInfos)
    {
        let colors = parent.getThemeColors()

        painter.setParams(.Antialiased)
        painter.fillRoundRect(rect, 8, 8, colors.wnd_Bk)

        if texture.isValid()
        {
            var txtRect = rect
            txtRect.inflate(-RecentPadding * 0.5)

            let ratio = Math.min(txtRect.width / texture.width, txtRect.height / texture.height)

            txtRect.x      = rect.horzCenter() - (texture.width * 0.5 * ratio)
            txtRect.y      = rect.vertCenter() - (texture.height * 0.5 * ratio)
            txtRect.width  = texture.width * ratio
            txtRect.height = texture.height * ratio

            with painter
            {
                .fillRect(txtRect, Argb.LightGray)
                .fillRect(txtRect, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
                .setInterpolationMode(.Linear)
                .drawTexture(txtRect, texture)
            }
        }

        if infos.linked != null
        {
            let backColor = infos.linkedUpToDate ? colors.bk : ColorYellow
            var icon11    = Icon.from(&g_Main.icons48, 21)
            icon11.sizeX, icon11.sizeY = 24
            icon11.paint(painter, rect.x + 4, rect.y + 4, backColor)

            var icon12 = Icon.from(&g_Main.icons48, 22)
            icon12.sizeX, icon12.sizeY = 24
            icon12.paint(painter, rect.x + 4, rect.y + 4, backColor.getContrasting())

            var icon = parent.getTheme().getIcon24(.Link)
            icon.sizeX, icon.sizeY = 16
            icon.paint(painter, rect.x + 8, rect.y + 8, backColor.getContrasting())
        }

        if infos.hot do
            painter.drawRoundRect(rect, 8, 8, colors.hilightLight, 2)
        if infos.selected do
            painter.drawRoundRect(rect, 8, 8, colors.hilightLight, 4)
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        let painter    = evt.bc.painter
        let clientRect = .getClientRectPadding()

        var x = clientRect.x
        for item, idx in .items
        {
            let w = clientRect.height * 4.0 / 3

            let rect = Math.Rectangle{x, clientRect.y, w, clientRect.height}
            item.rect = rect

            with var infos: RecentInfos
            {
                .hot            = idx == me.hotItem
                .selected       = idx == me.selected
                .linkedUpToDate = item.linkedUpToDate
                .linked         = item.linked
            }

            paintRecent(me, painter, item.preview, rect, infos)
            x = rect.right() + RecentPadding
        }

        .recentWnd.setScrollSize(x, 0)
    }
}

struct RecentWnd
{
    using scrollWnd:     ScrollWnd
    main:                *MainWnd
    recentView:          *RecentView
    timer:               *Gui.Timer
    loadTimer:           *Gui.Timer
    pendingRecentFiles:  Array'String
    pendingRecentIndex:  u64
    loadDone:            bool
    prepareLoadRecent:   bool
}

impl IWnd for RecentWnd
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .timer do
            .getApp().deleteTimer(.timer)
        if .loadTimer do
            .getApp().deleteTimer(.loadTimer)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .loadTimer
        {
            .getApp().deleteTimer(evt.timer)
            .loadTimer = null
            if .prepareLoadRecent
            {
                .prepareLoadRecent = false
                .loadRecent()
            }
            else do
                .loadNextRecent()
            return
        }

        let maybeCapture = .main.getCapture()
        if maybeCapture
        {
            let capture = assume maybeCapture
            if !capture.changed do
                return

            capture.computePreview()
            let item = .recentView.items[.recentView.selected]
            .getApp().getRenderer().removeTexture(&item.preview)
            item.preview = .getApp().getRenderer().addImage(capture.preview)
            .invalidate()

            .main.libWnd.view.updateRecent(capture)

            .main.saveCapture(capture)
        }

        .getApp().deleteTimer(evt.timer)
        .timer = null
    }
}

impl RecentWnd
{
    func create(parent: *Wnd, main: *MainWnd)->*RecentWnd
    {
        with let recent = Wnd.create'RecentWnd(parent, {0, 0, 0, PreviewHeight + RecentPadding * 2})
        {
            .scrollWndFlags |= .SmallBar | .ForceHorizontal
            .backgroundStyle = .Window
            .main            = main
            .style.addStyleSheetColors("scrollBar_Bk $view_Bk")

            .recentView           = recent.createView'RecentView()
            .recentView.padding   = RecentPadding
            .recentView.main      = main
            .recentView.recentWnd = recent
            .view.backgroundStyle = .View
        }

        return recent
    }

    mtd scheduleLoadRecent()
    {
        if .loadDone or .loadTimer do
            return
        .prepareLoadRecent = true
        .loadTimer         = .getApp().addTimer(100'ms, me)
    }

    mtd loadRecent()
    {
        if .loadDone do
            return
        .loadDone = true

        if !g_Library.loaded do
            g_Library.fill()
        g_Library.onDeleteFile += func|self = me|(file)
        {
            for it, i in self.recentView.items
            {
                if it.file == file
                {
                    // Remove from recent
                    self.recentView.items.deletePtr(it)
                    self.recentView.items.removeAtOrdered(i)

                    // Select new one
                    if self.recentView.selected == i
                    {
                        self.recentView.selected = Swag.U64.Max
                        self.recentView.select(i)
                    }

                    break
                }
            }
        }

        var res = g_Library.files
        res.sort(func(a, b)
        {
            return b.lastWriteTime <=> a.lastWriteTime
        })

        for r in res
        {
            .pendingRecentFiles.add(r.fullname)
            if .pendingRecentFiles.count >= MaxRecent do
                break
        }

        .scheduleLoadNextRecent()
    }

    mtd scheduleLoadNextRecent()
    {
        if .loadTimer or .pendingRecentIndex >= .pendingRecentFiles.count do
            return
        .prepareLoadRecent = false
        .loadTimer = .getApp().addTimer(1'ms, me)
    }

    mtd loadNextRecent()
    {
        if .pendingRecentIndex >= .pendingRecentFiles.count do
            return

        let idx     = .pendingRecentIndex
        let capture = catch .addRecent(.pendingRecentFiles[idx], front: false)
        defer #err Memory.delete(capture)
        if @err == null
        {
            if idx == 0 and !.main.editWnd.editView.capture
            {
                .recentView.selected = 0
                .main.editWnd.editView.setCapture(capture)
            }
            else do
                Memory.delete(capture)
        }

        .pendingRecentIndex += 1
        .scheduleLoadNextRecent()
    }

    mtd updateRecent()
    {
        if .recentView.selected >= .recentView.items.count do
            return

        if .timer do
            .getApp().deleteTimer(.timer)
        .timer = .getApp().addTimer(1's, me)

        let capture = .main.getCapture()
        if !capture do
            return

        let item = .recentView.items[.recentView.selected]
        item.linked         = capture.linkedImage
        item.linkedUpToDate = capture.linkedUpToDate
        .invalidate()
    }

    mtd removeRecent()
    {
        if .recentView.selected >= .recentView.items.count do
            return

        let item = .recentView.items[.recentView.selected]

        // Be sure there's no pending save
        if .timer do
            .getApp().deleteTimer(.timer)
        .timer = null

        // Delete file
        g_Library.removeFile(item.file)
    }

    mtd addRecent(file: string, front = true, sel = false)->*Capture throw
    {
        let capture = Capture.load(file)
        .addRecent(capture.file, capture.preview, front, sel, capture.linkedUpToDate, capture.linkedImage)

        // Too much recent. Remove the oldest
        if front and .recentView.items.count > MaxRecent
        {
            let back = .recentView.items.back()
            if back.preview.isValid() do
                .getApp().getRenderer().removeTexture(&back.preview)
            .recentView.items.deletePtr(back)
            .recentView.items.count -= 1
        }

        return capture
    }

    mtd addRecent(file: string, preview: Image, front = true, sel = false, linkedUpToDate = true, linked: string = null)
    {
        // Already there ?
        for it, i in .recentView.items
        {
            if it.file == file
            {
                var idxSel = i

                // Move the item to the first position
                if front and i
                {
                    .recentView.items.swap(0, i)
                    idxSel = 0
                }

                if sel do
                    .recentView.select(idxSel, true)

                it.linked = linked
                return
            }
        }

        let item = .recentView.items.newPtr()
        item.preview        = .getApp().getRenderer().addImage(preview)
        item.file           = file
        item.linked         = linked
        item.linkedUpToDate = linkedUpToDate
        if front
        {
            .recentView.items.insertAt(0, item)
            if sel
            {
                .recentView.select(0, force: true)
                .setScrollPos(0, 0)
            }
        }
        else
        {
            .recentView.items.add(item)
            if sel do
                .recentView.select(.recentView.items.count - 1, force: true)
        }

        .invalidate()
    }
}
