using Threading, Time

internal var g_UpdatingLib: bool
internal var g_DirtyList: bool = true
internal const ItemMargin = 8.0

struct LibraryItem
{
    fi:           File.FileInfo
    capture:      *Capture
    texture:      Texture
    rect:         Math.Rectangle
    visible:      bool
    filtered:     bool
}

impl LibraryItem
{
    mtd opDrop()
    {
        Memory.delete(.capture)
    }
}

struct LibraryView
{
    using wnd:       Wnd
    scrollWnd:       *ScrollWnd
    libWnd:          *LibraryWnd
    mainWnd:         *MainWnd
    allItems:        ArrayPtr'LibraryItem
    items:           Array'*LibraryItem
    mutexLoaded:     Sync.Mutex
    thread:          Thread
    hotItem          = Swag.U32.Max
    focusItem        = Swag.U32.Max
    selModel:        SelModel
    filterYear:      u64
    filterMonth:     u64
    filterDay:       u64
    imgSpin:         *ImageRect
}

impl IWnd for LibraryView
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .MouseLeave
        {
            .hotItem = Swag.U32.Max
            .invalidate()
            return
        }

        if evt.kind == .MouseWheel do
            evt.accepted = false

        var pos = .surfaceToLocal(evt.surfacePos)
        pos += .scrollWnd.getScrollPos()

        // Hit test
        var ht = Swag.U32.Max
        for it, idx in .items
        {
            if it.rect.contains(pos)
            {
                ht = cast(u32) idx
                break
            }
        }

        if ht != .hotItem
        {
            .invalidate()
            .hotItem = ht
        }

        let shiftPressed = cast(bool) (evt.modifiers & .Shift)
        let ctrlPressed  = cast(bool) (evt.modifiers & .Control)

        if evt.kind == .MouseReleased and .hotItem != Swag.U32.Max and evt.button == .Left
        {
            if !ctrlPressed and !shiftPressed do
                .selModel.unselectAll()

            if shiftPressed and .focusItem < .items.count do
                .selModel.select(.hotItem, .focusItem, true)
            elif ctrlPressed and .selModel.isSelected(.hotItem) do
                .selModel.select(.hotItem, false)
            else do
                .selModel.select(.hotItem, true)

            .focusItem = .hotItem
            .invalidate()
            .setFocus()
        }

        if evt.kind == .MouseDoubleClick and .focusItem < .items.count and evt.button == .Left
        {
            let item = .items[.focusItem]
            .mutexLoaded.lock()
            let capture = item.capture
            .mutexLoaded.unlock()
            if !capture do
                return

            catch File.touch(item.fi.fullname)
            .mainWnd.recentWnd.addRecent(item.fi.fullname, capture.preview, front: true, sel: true, linked: capture.linkedImage)
            .mainWnd.recentWnd.setScrollPos(0, 0)
            .mainWnd.swapLibraryMode()
            .mainWnd.updateState()
        }

        if evt.kind == .MousePressed and evt.button == .Right and .focusItem < .items.count
        {
            with let menu = MenuCtrl.createPopup(me)
            {
                .addItem(ActionFile.DeleteCapture)
                .addSeparator()
                .addItem(ActionFile.CaptureFileLocation)
                .addItem(ActionFile.LinkedFileLocation)
                .addSeparator()
                .addItem(ActionFile.FileDetails)
            }

            discard menu.doModal(evt.surfacePos, autoDestroy: true)
        }
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        if !g_UpdatingLib do
            .imgSpin.hide()

        let painter    = evt.bc.painter
        let clientRect = .getClientRectPadding()

        var x = clientRect.x
        var y = clientRect.y

        let (w, h) = .getPreviewSize()
        if g_DirtyList
        {
            g_DirtyList = false
            .filter()
        }

        let spos = .scrollWnd.getScrollPos()
        for it, i in .items
        {
            it.visible = true
            if y + h < spos.y do
                it.visible = false
            if y > spos.y + .position.height do
                it.visible = false

            // Retrieve the loaded capture if it exists
            .mutexLoaded.lock()
            let capture = it.capture
            .mutexLoaded.unlock()

            // We have a capture but not yet a texture. Create it.
            if capture and !it.texture.isValid() do
                it.texture = evt.bc.renderer.addImage(capture.preview)

            it.rect = Math.Rectangle{x, y, w, h}
            let selected = .selModel.isSelected(cast() i)

            with var infos: RecentInfos
            {
                .hot      = i == me.hotItem
                .selected = selected
            }

            if capture
            {
                infos.linkedUpToDate = capture.linkedUpToDate
                infos.linked         = capture.linkedImage
            }

            RecentView.IWnd.paintRecent(me, painter, it.texture, it.rect, infos)

            // Waiting for texture
            if !it.texture.isValid()
            {
                let icon  = .getTheme().getIcon64(.HourGlass, 48)
                let color = Color.fromArgb(50, Argb.White)
                icon.paint(painter, it.rect.horzCenter() - icon.sizeX * 0.5, it.rect.vertCenter() - icon.sizeY * 0.5, color)
            }

            // Next item
            x += w + ItemMargin
            if x + w + ItemMargin >= clientRect.right()
            {
                x = clientRect.x
                y += h + ItemMargin
            }
        }

        .scrollWnd.setScrollSize(0, y + h + ItemMargin)
    }
}

impl LibraryView
{
    mtd const numImagesPerLine()->u32
    {
        let (w, ?) = .getPreviewSize()
        let clientRect = .getClientRectPadding()
        let n          = clientRect.width / (w + ItemMargin)
        return cast(u32) n
    }

    mtd const getPreviewSize()->{ w: f32, h: f32 }
    {
        var H: f32 = 128.0
        var W: f32 = 0
        switch .libWnd.previewSize
        {
        case Small:
            H = 128
            W = H * 4.0 / 3.0
        case Medium:
            H = 256
            W = H * 4.0 / 3.0
        case Big:
            H = 512
            W = H * 4.0 / 3.0
        }

        return {W, H}
    }

    mtd updateRecent(capture: *Capture)
    {
        for it in .items
        {
            if capture.file == it.fi.fullname
            {
                if it.capture and it.texture.isValid()
                {
                    .getApp().getRenderer().removeTexture(&it.texture)
                    it.texture = .getApp().getRenderer().addImage(capture.preview)
                }

                break
            }
        }
    }

    mtd filter()
    {
        .items.clear()
        for it in .allItems
        {
            it.filtered = true

            .mutexLoaded.lock()
            let capture = it.capture
            .mutexLoaded.unlock()

            if !capture
            {
                it.filtered = false
                .items.add(it)
                continue
            }
            if !capture.linkedImage.isEmpty() and !.libWnd.showLinkedImage do
                continue
            if capture.linkedImage.isEmpty() and !.libWnd.showUnLinkedImage do
                continue
            if capture.linkedUpToDate and !capture.linkedImage.isEmpty() and !.libWnd.showUpToDateLinkedImage do
                continue
            if !capture.linkedUpToDate and !capture.linkedImage.isEmpty() and !.libWnd.showUnSavedLinkedImage do
                continue

            it.filtered = false
            .items.add(it)
        }

        .invalidate()
    }

    mtd loadOne(it: *LibraryItem)
    {
        let capture = catch Capture.load(it.fi.fullname, preview: true)
        if !capture do
            return

        capture.haar = ImageStatistics.quickExtractHaarFeatures(capture.preview, 32)
        g_DirtyList  = true

        .mutexLoaded.lock()
        it.capture = capture
        .mutexLoaded.unlock()
    }

    mtd loadFiles(th: Thread)
    {
        // Work on a copy, as 'items' can be changed by sorting during loading
        var copy: Array'*LibraryItem
        for it in .allItems do
            copy.add(it)

        for it in copy
        {
            if th.requestEnd do
                break
            if it.capture or !it.visible do
                continue

            .loadOne(it)
            .postInvalidateEvent()
        }

        for it in copy
        {
            if th.requestEnd do
                break
            if it.capture do
                continue

            .loadOne(it)
            if (@index & 15) == 0 do
                .postInvalidateEvent()
        }

        .postInvalidateEvent()
        g_UpdatingLib = false
    }

    mtd sortSimilar()
    {
        if .items.isEmpty() do
            return

        var remaining: Array'*LibraryItem
        for it in .items do
            remaining.add(it)
        if remaining.isEmpty() do
            return

        var nitems: Array'*LibraryItem

        var toCompare: *LibraryItem
        while !remaining.isEmpty()
        {
            if !toCompare or !toCompare.capture or toCompare.filtered
            {
                toCompare = remaining.front()
                remaining.removeAt(0)
                nitems.add(toCompare)
                continue
            }

            var best:      f32
            var bestI:     u64
            var foundMatch = false
            for it in remaining where it.capture and toCompare.capture.haar.size == it.capture.haar.size
            {
                let similarity = ImageStatistics.quickCompareHaarCoefficients(toCompare.capture.haar, it.capture.haar)
                if similarity > best
                {
                    best       = similarity
                    bestI      = @index
                    foundMatch = true
                }
            }

            if foundMatch
            {
                toCompare = remaining[bestI]
                nitems.add(toCompare)
                remaining.removeAt(bestI)
            }
            else
            {
                toCompare = remaining.front()
                remaining.removeAt(0)
                nitems.add(toCompare)
            }
        }

        .mutexLoaded.lock()
        for it, i in nitems do
            .items[i] = nitems[i]
        .mutexLoaded.unlock()
    }

    mtd sortFiles()
    {
        .items.sort(func|libWnd = me.libWnd|(a, b)
        {
            var value: s32

            switch libWnd.sortMethod
            {
            case Recent:
                value = b.fi.lastWriteTime <=> a.fi.lastWriteTime
            case FileSize:
                value = b.fi.size <=> a.fi.size
            }

            if libWnd.invertSort do
                return -value
            return value
        })
    }

    mtd sort()
    {
        if .items.isEmpty() do
            return

        Cursor.wait()

        if .libWnd.sortMethod == .Similar do
            .sortSimilar()
        else do
            .sortFiles()

        .invalidate()
    }

    mtd fill() throw
    {
        if .thread.isValid()
        {
            .thread.safeForceEnd()
            .thread.wait()
        }

        // Filter
        var res: Array'File.FileInfo
        for fi in g_Library.files
        {
            if (.filterYear == 0 or fi.lastWriteTime.year == .filterYear) and
               (.filterMonth == 0 or fi.lastWriteTime.month == .filterMonth) and
               (.filterDay == 0 or fi.lastWriteTime.day == .filterDay)
            {
                res.add(fi)
            }
        }

        let renderer = .getApp().getRenderer()
        // Release textures over the full set, not just the filtered '.items': items
        // filtered out are absent from '.items' and would leak their GPU texture
        // when 'allItems' is cleared below.
        for it in .allItems do
            renderer.removeTexture(&it.texture)

        // Add items
        .allItems.clear()
        .allItems.reserve(res.count)
        for fi in res
        {
            let ptr = .allItems.addNewPtr()
            ptr.fi = fi
        }

        .filter()
        .sort()

        .hotItem = Swag.U32.Max
        .clearSelection()

        g_UpdatingLib = true
        .imgSpin.show()

        // Launch thread to read all captures
        try
        {
            .thread.init(func|view = me|(th: Thread) { view.loadFiles(th); })
            .thread.start()
        }

        .invalidate()
    }

    mtd clearSelection()
    {
        .focusItem = Swag.U32.Max
        .selModel.unselectAll()
    }

    mtd setFocusItem(focus: u32)
    {
        .selModel.unselectAll()
        .focusItem = focus
        .selModel.select(.focusItem, .focusItem, true)
        .invalidate()
    }

    mtd scrollToFocus()
    {
        if .focusItem == Swag.U32.Max do
            return
        if .items[.focusItem].visible do
            return
        .scrollWnd.setScrollPos(0, .items[.focusItem].rect.y - 4)
    }
}
