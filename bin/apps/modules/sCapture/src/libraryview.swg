using Threading, Time

// Returns the localized wording used where a vector rating glyph cannot be painted.
func ratingLabel(rating: u8)->String
{
    switch rating
    {
    case 0: return appStrings().act_NoRating
    case 1: return appStrings().act_Rating1
    case 2: return appStrings().act_Rating2
    case 3: return appStrings().act_Rating3
    case 4: return appStrings().act_Rating4
    default: return appStrings().act_Rating5
    }
}

internal var g_UpdatingLib: bool
internal var g_DirtyList: bool = true
internal const ItemMargin = 8.0
internal const RatingGlyphSize = 12.0
internal const RatingGlyphGap  = 2.0

// How often the visible set is rebuilt while the previews are still streaming in. Each
// loaded capture marks the list dirty, so without a cadence the rebuild runs on every
// frame of the load, and each rebuild is proportional to the whole library.
internal const ListRefreshDelay = 200

enum LibraryItemKind
{
    Capture
    Image
}

struct LibraryItem
{
    fi:       File.FileInfo
    kind:     LibraryItemKind
    capture:  #null *Capture
    image:    Image
    width:    s32
    height:   s32
    haar:     ImageStatistics.HaarFeatures
    texture:  Texture
    rect:     Math.Rectangle
    visible:  bool
    filtered: bool
    loaded:   bool
}

impl LibraryItem
{
    mtd opDrop()
    {
        if .texture.isValid() do
            g_App.renderer.removeTexture(&.texture)
        Memory.delete(.capture)
    }
}

struct LibraryView
{
    using wnd: Wnd
    #[Swag.Late]
    {
        scrollWnd: *ScrollWnd
        libWnd:    *LibraryWnd
        mainWnd:   *MainWnd
    }

    allItems:    ArrayPtr'LibraryItem
    items:       Array'*LibraryItem
    mutexLoaded: Sync.Mutex
    thread:      Thread
    hotItem   = Swag.U32.Max
    focusItem = Swag.U32.Max
    selModel:    SelModel
    filterYear:  u64
    filterMonth: u64
    filterDay:   u64
    listRefresh: Time.Stopwatch
    #[Swag.Late]
    imgSpin: *Spinner
}

impl IWnd for LibraryView
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Leave
        {
            .hotItem = Swag.U32.Max
            .invalidate()
            return
        }

        if evt.kind == .Wheel do
            evt.accepted = false

        var pos = .surfaceToLocal(evt.surfacePos)
        pos += .scrollWnd.scrollPosition()

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

        if evt.kind == .Released and .hotItem != Swag.U32.Max and evt.button == .Left
        {
            if !ctrlPressed and !shiftPressed do
                .selModel.clear()

            if shiftPressed and .focusItem < .items.count do
                .selModel.selectRange(.hotItem, .focusItem)
            elif ctrlPressed and .selModel.isSelected(.hotItem) do
                .selModel.unselect(.hotItem)
            else do
                .selModel.select(.hotItem)

            .focusItem = .hotItem
            .invalidate()
            .setFocus()
        }

        if evt.kind == .DoubleClick and .focusItem < .items.count and evt.button == .Left
        {
            // Trashed captures are not editable; they must be restored first.
            if .libWnd.trashMode do
                return

            .openItem(.items[.focusItem])
        }

        if evt.kind == .Pressed and evt.button == .Right and (.hotItem < .items.count or .focusItem < .items.count)
        {
            if .hotItem < .items.count and !.selModel.isSelected(.hotItem)
            {
                .setFocusItem(.hotItem)
                .focusItem = .hotItem
            }

            let focused        = .items[.focusItem]
            let focusedCapture = focused.capture
            with let menu = MenuCtrl.createPopup(me)
            {
                if me.libWnd.trashMode
                {
                    .addItem(ActionLibTrash.Restore)
                    .addSeparator()
                    .addItem(ActionLibTrash.DeleteForever)
                }
                elif focused.kind == .Image
                {
                    .addItem(appStrings().act_OpenSelected, "sCapture.library.open")
                    .addSeparator()
                    .addItem(appStrings().act_LocateImage, "sCapture.library.reveal")
                }
                else
                {
                    .addItem(appStrings().act_OpenSelected, "sCapture.library.open")
                    .addSeparator()
                    .addItem(ActionFile.CopyImage)
                    .addItem(appStrings().act_ExportSelected, "sCapture.library.export")
                    .addItem(ActionFile.RenameCapture)
                    .addItem(appStrings().act_EditTags, "sCapture.library.tags")
                    .addItem(appStrings().act_FavoriteCapture, "sCapture.library.favorite", checked: focusedCapture and focusedCapture.favorite)

                    with let rating = MenuCtrl.createPopup(menu, owner: me)
                    {
                        .addItem(appStrings().act_NoRating, "sCapture.library.rating.0", checked: focusedCapture and focusedCapture.rating == 0)
                        .addItem(appStrings().act_Rating1, "sCapture.library.rating.1", checked: focusedCapture and focusedCapture.rating == 1)
                        .addItem(appStrings().act_Rating2, "sCapture.library.rating.2", checked: focusedCapture and focusedCapture.rating == 2)
                        .addItem(appStrings().act_Rating3, "sCapture.library.rating.3", checked: focusedCapture and focusedCapture.rating == 3)
                        .addItem(appStrings().act_Rating4, "sCapture.library.rating.4", checked: focusedCapture and focusedCapture.rating == 4)
                        .addItem(appStrings().act_Rating5, "sCapture.library.rating.5", checked: focusedCapture and focusedCapture.rating == 5)
                        menu.addPopup(appStrings().act_Rating, rating)
                    }

                    .addSeparator()
                    .addItem(ActionFile.DeleteCapture)
                    .addSeparator()
                    .addItem(ActionFile.CaptureFileLocation)
                    .addItem(ActionFile.LinkedFileLocation)
                    .addSeparator()
                    .addItem(ActionFile.FileDetails)
                }
            }

            let result = menu.doModal(evt.surfacePos, autoDestroy: true)
            if !result do
                return
            switch result!
            {
            case "sCapture.library.open":     .openItem(focused)
            case "sCapture.library.reveal":   discard Env.showInFileExplorer(focused.fi.fullname)
            case "sCapture.library.tags":     .libWnd.editSelectedTags()
            case "sCapture.library.export":   .libWnd.exportSelected()
            case "sCapture.library.favorite": .libWnd.toggleSelectedFavorite()
            case "sCapture.library.rating.0": .libWnd.rateSelected(0)
            case "sCapture.library.rating.1": .libWnd.rateSelected(1)
            case "sCapture.library.rating.2": .libWnd.rateSelected(2)
            case "sCapture.library.rating.3": .libWnd.rateSelected(3)
            case "sCapture.library.rating.4": .libWnd.rateSelected(4)
            case "sCapture.library.rating.5": .libWnd.rateSelected(5)
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if !g_UpdatingLib do
            .imgSpin.hide()

        let painter    = evt.paintContext.painter
        let clientRect = .paddedClientRect()

        var x = clientRect.x
        var y = clientRect.y

        let {w, h} = .getPreviewSize()
        if g_DirtyList and .takeListRefresh()
        {
            .filter()
            .sort()
            .libWnd.refreshAutomaticFilters()
        }

        let spos = .scrollWnd.scrollPosition()
        for it, i in .items
        {
            it.visible = true
            if y + h < spos.y do
                it.visible = false
            if y > spos.y + .position.height do
                it.visible = false

            // Retrieve the loaded capture if it exists
            .mutexLoaded.lock()
            let capture    = it.capture
            let image      = it.image
            let itemLoaded = it.loaded
            .mutexLoaded.unlock()

            // SCC items retain their compressed PNG, not a decoded image plus a texture for
            // every file in the library. Materialize only what is visible, upload it, then
            // release the transient pixels. Off-screen textures are evicted by the same rule.
            if capture and !it.visible and it.texture.isValid() and !capture.previewBytes.isEmpty()
            {
                evt.paintContext.renderer.removeTexture(&it.texture)
            }
            elif capture and it.visible and !it.texture.isValid()
            {
                catch capture.materializePreview()
                if capture.preview.isValid()
                {
                    it.texture = evt.paintContext.renderer.addImage(capture.preview)
                    if !capture.previewBytes.isEmpty() do
                        capture.preview = {}
                }
            }
            elif it.kind == .Image and it.visible and !it.texture.isValid() and image.isValid() do
                it.texture = evt.paintContext.renderer.addImage(image)

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
                infos.showLinked     = .libWnd.showLinkOverlay
            }

            RecentView.IWnd.paintRecent(me, painter, it.texture, it.rect, infos)

            // User-given name, drawn along the bottom of the thumbnail with a soft
            // shadow so it stays readable over any background.
            var label = ""
            if capture and !capture.title.isEmpty() do
                label = capture.title
            elif capture and !capture.sourceApplication.isEmpty() do
                label = capture.sourceApplication
            elif it.kind == .Image do
                label = Path.fileName(it.fi.fullname) orelse ""

            if @countof(label)
            {
                let font = me .font().regular!
                let cx   = it.rect.horzCenter()
                let by   = it.rect.bottom() - 8
                painter.drawStringCenter(cx + 1, by + 1, label, font, Color.fromArgb(0xC0, Argb.Black))
                painter.drawStringCenter(cx, by, label, font, Argb.White)
            }

            if it.kind == .Image
            {
                let font = me .theme().res.fontDefaultFs.regular!
                let text = appStrings().ui_ImageBadge
                let ms   = Painter.measureString(text, font)
                let rc   = Math.Rectangle{it.rect.x + 8, it.rect.y + 8, ms.width + 12, font.height + 4}
                painter.fillRect(rc, .themeColors().wnd_Bk)
                painter.drawString(rc.x + 6, rc.y + 2, text, font, .themeColors().label_TextLight)
            }

            if capture and capture.favorite
            {
                let font = me .theme().res.fontDefault.bold!
                let text = "♥"
                let ms = Painter.measureString(text, font)
                painter.drawString(it.rect.right() - ms.width - 8, it.rect.y + 8, text, font, .themeColors().hilight)
            }

            if capture and capture.rating and .libWnd.showRatingOverlay
            {
                let star  = .mainWnd.icon(.RatingStar, RatingGlyphSize)
                let width = cast(f32) capture.rating * RatingGlyphSize + cast(f32) (capture.rating - 1) * RatingGlyphGap
                var sx    = it.rect.right() - width - 8
                let sy    = it.rect.y + (capture.favorite ? 24 : 8)
                for capture.rating
                {
                    star.paint(painter, sx, sy, .themeColors().hilight)
                    sx += RatingGlyphSize + RatingGlyphGap
                }
            }

            // Loading, a legacy preview-less capture, or an image the decoder rejected.
            if !it.texture.isValid()
            {
                var icon = .theme().icon(.HourGlass, 48)
                if itemLoaded and it.kind == .Capture do
                    icon = .mainWnd.icon(.Archive, 48)
                elif itemLoaded do
                    icon = .theme().icon(.Warning, 48)
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
    // Answers whether this frame rebuilds the visible set, and consumes the dirty mark when it
    // does.
    //
    // Every loaded capture marks the list dirty and asks for a repaint, and the spinner repaints
    // on its own besides, so a load of a large library asks for one full rebuild per frame. The
    // list converges just as well on a fixed cadence, and the last state is never missed: the
    // loader clears 'g_UpdatingLib' before its final repaint, and that frame rebuilds at once.
    mtd takeListRefresh()->bool
    {
        if g_UpdatingLib and .listRefresh.isRunning() and .listRefresh.elapsedMilliseconds() < ListRefreshDelay do
            return false

        g_DirtyList = false
        .listRefresh.restart()
        return true
    }

    mtd stopLoading()
    {
        if !.thread.isValid() do
            return
        .thread.safeForceEnd()
        .thread.wait()
    }

    mtd startLoading() fail
    {
        var hasPending: bool
        for it in .allItems where !it!.loaded do
            hasPending = true

        if !hasPending
        {
            g_UpdatingLib = false
            return
        }

        g_UpdatingLib = true
        if @isset(.imgSpin) do
            .imgSpin.show()
        try
        {
            .thread.init(func|view = me|(th: Thread) { view.loadFiles(th); })
            .thread.start()
        }
    }

    mtd openItem(item: *LibraryItem)
    {
        if item.kind == .Image
        {
            .mainWnd.loadExternalImage(item.fi.fullname)
            return
        }

        .mutexLoaded.lock()
        let capture = item.capture
        .mutexLoaded.unlock()
        if !capture do
            return

        catch capture.materializePreview()
        catch File.touch(item.fi.fullname)
        .mainWnd.recentWnd.addRecent(item.fi.fullname, capture.preview, front: true, sel: true, linked: capture.linkedImage)
        if !capture.previewBytes.isEmpty() do
            capture.preview = {}
        .mainWnd.recentWnd.setScrollPos(0, 0)
        .mainWnd.swapLibraryMode()
        .mainWnd.updateState()
    }

    mtd const numImagesPerLine()->u32
    {
        let {w, ?}     = .getPreviewSize()
        let clientRect = .paddedClientRect()
        let n          = clientRect.width / (w + ItemMargin)
        return cast(u32) n
    }

    mtd const getPreviewSize()->{ w: f32, h: f32 }
    {
        var H: f32 = 128.0
        var W: f32 = 0
        switch .libWnd.previewSize
        {
        case .Small:
            H = 128
            W = H * 4.0 / 3.0

        case .Medium:
            H = 256
            W = H * 4.0 / 3.0

        case .Big:
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
                if it.capture
                {
                    it.capture.previewBytes.clear()
                    it.capture.preview = capture.preview
                }
                if it.capture and it.texture.isValid()
                {
                    .app().renderer.removeTexture(&it.texture)
                    it.texture = .app().renderer.addImage(capture.preview)
                }

                break
            }
        }
    }

    // Case-insensitive substring test used by the library search box. Matches the
    // capture title, the linked image path and the capture file name so the user can
    // find a capture by any of the names it is known under.
    mtd const matchSearch(it: *LibraryItem, capture: #null *Capture, search: String)->bool
    {
        if search.isEmpty() do
            return true
        if capture
        {
            if Utf8.indexOf(capture.title.toSlice(), search, 0, .Latin1NoCase) != Swag.U64.Max do
                return true
            if Utf8.indexOf(capture.linkedImage.toSlice(), search, 0, .Latin1NoCase) != Swag.U64.Max do
                return true
            if Utf8.indexOf(capture.sourceApplication.toSlice(), search, 0, .Latin1NoCase) != Swag.U64.Max do
                return true
            if Utf8.indexOf(capture.sourceExecutable.toSlice(), search, 0, .Latin1NoCase) != Swag.U64.Max do
                return true
            if Utf8.indexOf(capture.sourceWindowTitle.toSlice(), search, 0, .Latin1NoCase) != Swag.U64.Max do
                return true
            if Utf8.indexOf(capture.sourceWindowClass.toSlice(), search, 0, .Latin1NoCase) != Swag.U64.Max do
                return true
            for tag in capture.tags where Utf8.indexOf(tag.toSlice(), search, 0, .Latin1NoCase) != Swag.U64.Max do
                return true
        }

        if Utf8.indexOf(it.fi.fullname.toSlice(), search, 0, .Latin1NoCase) != Swag.U64.Max do
            return true
        return false
    }

    mtd filter()
    {
        var selectedFiles: Array'String
        var focusedFile:   String
        for item, i in .items
        {
            if .selModel.isSelected(cast() i) do
                selectedFiles.add(item.fi.fullname)
            if i == .focusItem do
                focusedFile = item.fi.fullname
        }

        .items.clear()
        let search = .libWnd.searchText.toString()

        // Both folders are resolved once for the whole pass. They do not change while it runs,
        // and asking for them per item is a path build — and, for the default library, a shell
        // lookup — repeated as many times as the library holds captures.
        let dateFilterApplies = .libWnd.currentFolder() == Library.getFolder()

        for it in .allItems
        {
            let itn = it!
            itn.filtered = true

            .mutexLoaded.lock()
            let capture    = itn.capture
            let itemLoaded = itn.loaded
            .mutexLoaded.unlock()

            if dateFilterApplies and
               ((.filterYear != 0 and itn.fi.lastWriteTime.year != .filterYear) or
                (.filterMonth != 0 and itn.fi.lastWriteTime.month != .filterMonth) or
                (.filterDay != 0 and itn.fi.lastWriteTime.day != .filterDay))
            {
                continue
            }

            if (.libWnd.contentFilter == .Captures or .libWnd.contentFilter == .ScreenCaptures or .libWnd.contentFilter == .ImportedCaptures) and itn.kind != .Capture do
                continue
            if .libWnd.contentFilter == .Images and itn.kind != .Image do
                continue

            if !itemLoaded
            {
                // Nothing is known about an item until its preview loads. While a search
                // is active hide it (it re-appears once loaded if it matches) so results
                // are not padded with unloaded, possibly non-matching, captures.
                if @countof(search) != 0 or .libWnd.contentFilter == .ScreenCaptures or .libWnd.contentFilter == .ImportedCaptures or .libWnd.favoritesOnly or .libWnd.minimumRating or !.libWnd.applicationFilter.isEmpty() or !.libWnd.tagFilter.isEmpty() do
                    continue
                itn.filtered = false
                .items.add(itn)
                continue
            }

            switch .libWnd.contentFilter
            {
            case .ScreenCaptures where !capture or capture.sourceKind != .Screen: continue
            case .ImportedCaptures where !capture or (capture.sourceKind != .ImageFile and capture.sourceKind != .Clipboard): continue
            }

            if itn.kind == .Image
            {
                if .libWnd.favoritesOnly or .libWnd.minimumRating or !.libWnd.applicationFilter.isEmpty() or !.libWnd.tagFilter.isEmpty() do
                    continue
                if !.matchSearch(itn, null, search) do
                    continue
                itn.filtered = false
                .items.add(itn)
                continue
            }

            let loaded = capture
            if !loaded do
                continue
            if !loaded.linkedImage.isEmpty() and !.libWnd.showLinkedImage do
                continue
            if loaded.linkedImage.isEmpty() and !.libWnd.showUnLinkedImage do
                continue
            if loaded.linkedUpToDate and !loaded.linkedImage.isEmpty() and !.libWnd.showUpToDateLinkedImage do
                continue
            if !loaded.linkedUpToDate and !loaded.linkedImage.isEmpty() and !.libWnd.showUnSavedLinkedImage do
                continue
            if .libWnd.favoritesOnly and !loaded.favorite do
                continue
            if loaded.rating < .libWnd.minimumRating do
                continue
            if !.libWnd.applicationFilter.isEmpty() and Utf8.compare(loaded.sourceApplication.toSlice(), .libWnd.applicationFilter, .Latin1NoCase) != 0 do
                continue
            if !.libWnd.tagFilter.isEmpty() and !loaded.hasTag(.libWnd.tagFilter) do
                continue
            if !.matchSearch(itn, loaded, search) do
                continue

            itn.filtered = false
            .items.add(itn)
        }

        .selModel.clear()
        .focusItem = Swag.U32.Max
        for item, i in .items
        {
            if selectedFiles.contains(item.fi.fullname) do
                .selModel.select(cast() i)
            if item.fi.fullname == focusedFile do
                .focusItem = cast(u32) i
        }

        .invalidate()
    }

    mtd loadOne(it: *LibraryItem)
    {
        if it.kind == .Capture
        {
            let capture:       #null *Capture = catch Capture.load(it.fi.fullname, preview: true, deferPreviewDecode: true)
            var haar:          ImageStatistics.HaarFeatures
            var width, height: s32
            if capture
            {
                catch capture.materializePreview()
                if capture.preview.isValid()
                {
                    haar = ImageStatistics.quickExtractHaarFeatures(capture.preview, 32)
                    if !capture.previewBytes.isEmpty() do
                        capture.preview = {}
                }
                width  = capture.width
                height = capture.height
            }

            .mutexLoaded.lock()
            it.capture = capture
            it.haar    = haar
            it.width   = width
            it.height  = height
            it.loaded  = true
            .mutexLoaded.unlock()
        }
        else
        {
            var image = catch Image.load(it.fi.fullname)
            var haar:          ImageStatistics.HaarFeatures
            var width, height: s32
            if image.isValid()
            {
                width  = image.width
                height = image.height
                haar   = ImageStatistics.quickExtractHaarFeatures(image, 32)
                if image.width > 512 or image.height > 512 do
                    image.resize(image.width >= image.height ? 512 : 0, image.height > image.width ? 512 : 0, .Bicubic)
            }

            .mutexLoaded.lock()
            it.image  = image
            it.haar   = haar
            it.width  = width
            it.height = height
            it.loaded = true
            .mutexLoaded.unlock()
        }

        g_DirtyList = true
    }

    mtd loadFiles(th: Thread)
    {
        // Work on a copy, as 'items' can be changed by sorting during loading
        var copy: Array'*LibraryItem
        for it in .allItems do
            copy.add(it!)

        for it in copy
        {
            if th.requestEnd do
                break
            if it.loaded or !it.visible do
                continue

            .loadOne(it)
            .postInvalidateEvent()
        }

        for it in copy
        {
            if th.requestEnd do
                break
            if it.loaded do
                continue

            .loadOne(it)
            if (@index & 15) == 0 do
                .postInvalidateEvent()
        }

        g_UpdatingLib = false
        .postInvalidateEvent()
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

        var toCompare: #null *LibraryItem
        while !remaining.isEmpty()
        {
            // A capture with no Haar features (no preview) can't anchor a similarity
            // comparison; pass it straight through so it never reaches the compare below.
            if !toCompare or toCompare.filtered or toCompare.haar.size == 0
            {
                toCompare = remaining.front()
                remaining.removeAt(0)
                nitems.add(toCompare)
                continue
            }

            var best:  f32
            var bestI: u64
            var foundMatch = false
            for it in remaining where toCompare.haar.size == it.haar.size
            {
                let similarity = ImageStatistics.quickCompareHaarCoefficients(toCompare.haar, it.haar)
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

        for it, i in nitems do
            .items[i] = it
    }

    mtd sortFiles()
    {
        // Only the active criterion is read. A comparator runs O(n log n) times per re-sort and
        // the list re-sorts while the previews stream in, so materializing every criterion — two
        // file names, two applications, two window titles — on each comparison was most of the
        // cost of a re-sort, whichever criterion was actually selected.
        .items.sort(func|libWnd = me.libWnd|(a, b)
        {
            var value: s32

            let captureA = a.capture
            let captureB = b.capture

            switch libWnd.sortMethod
            {
            case .Recent:
                let capturedA = captureA and captureA.capturedAt.isValid() ? captureA.capturedAt : a.fi.lastWriteTime
                let capturedB = captureB and captureB.capturedAt.isValid() ? captureB.capturedAt : b.fi.lastWriteTime
                value = capturedB <=> capturedA

            case .Modified:
                value = b.fi.lastWriteTime <=> a.fi.lastWriteTime

            case .Name:
                let nameA = captureA and !captureA.title.isEmpty() ? captureA.title.toString() : (Path.fileName(a.fi.fullname) orelse "")
                let nameB = captureB and !captureB.title.isEmpty() ? captureB.title.toString() : (Path.fileName(b.fi.fullname) orelse "")
                value = Utf8.compare(nameA, nameB, .Latin1NoCase)

            case .Application:
                let applicationA = captureA ? captureA.sourceApplication.toString() : ""
                let applicationB = captureB ? captureB.sourceApplication.toString() : ""
                value = Utf8.compare(applicationA, applicationB, .Latin1NoCase)

            case .WindowTitle:
                let windowA = captureA ? captureA.sourceWindowTitle.toString() : ""
                let windowB = captureB ? captureB.sourceWindowTitle.toString() : ""
                value = Utf8.compare(windowA, windowB, .Latin1NoCase)

            case .Dimensions:
                value = cast(u64) b.width * cast(u64) b.height <=> cast(u64) a.width * cast(u64) a.height

            case .FileSize:
                value = b.fi.size <=> a.fi.size
            }

            if !value do
                value = Utf8.compare(a.fi.fullname.toSlice(), b.fi.fullname.toSlice(), .Latin1NoCase)

            if libWnd.invertSort do
                return -value
            return value
        })
    }

    mtd sort()
    {
        if .items.isEmpty() do
            return

        var selectedFiles: Array'String
        var focusedFile:   String
        for item, i in .items
        {
            if .selModel.isSelected(cast() i) do
                selectedFiles.add(item.fi.fullname)
            if i == .focusItem do
                focusedFile = item.fi.fullname
        }

        .mutexLoaded.lock()
        defer .mutexLoaded.unlock()

        if .libWnd.sortMethod == .Similar do
            .sortSimilar()
        else do
            .sortFiles()

        .selModel.clear()
        .focusItem = Swag.U32.Max
        for item, i in .items
        {
            if selectedFiles.contains(item.fi.fullname) do
                .selModel.select(cast() i)
            if item.fi.fullname == focusedFile do
                .focusItem = cast(u32) i
        }

        .invalidate()
    }

    mtd fill() fail
    {
        .stopLoading()

        // Items come from the folder the breadcrumb currently points at. The sCapture home
        // folder uses the in-memory index (so the date sidebar and delete handlers stay in
        // sync, honouring the date filter); any other folder (the recycle bin included) is
        // listed straight from disk.
        var res: Array'File.FileInfo
        let cf = .libWnd.currentFolder()
        if Library.getFolder() == cf
        {
            for fi in g_Library.files do
                res.add(fi)
        }
        else
        {
            res = catch Library.enumerateSupportedFiles(cf)
        }

        // Add items
        // 'items' only borrows pointers owned by 'allItems'. Drop those borrows before their
        // owners so filter() never snapshots selection state through destroyed LibraryItems.
        .items.clear()
        .hotItem = Swag.U32.Max
        .clearSelection()
        .allItems.clear()
        .allItems.reserve(res.count)
        for fi in res
        {
            let ptr = .allItems.addNew()
            ptr.fi   = fi
            ptr.kind = Path.lowercaseExtension(fi.fullname) == ".scapture" ? .Capture : .Image
        }

        .filter()
        .sort()

        // Launch thread to read all captures
        try .startLoading()

        .invalidate()
    }

    mtd clearSelection()
    {
        .focusItem = Swag.U32.Max
        .selModel.clear()
    }

    mtd setFocusItem(focus: u32)
    {
        .selModel.clear()
        .focusItem = focus
        .selModel.select(.focusItem)
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
