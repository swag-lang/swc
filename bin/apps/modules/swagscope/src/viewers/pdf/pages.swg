#global internal
#global namespace Viewers.PdfDocument

using Core, Gui, Pixel

struct PageGallery
{
    using wnd: Wnd
    late panel: *Panel
    columns:    u64 = 1
    cell:       Math.Point = {120, 160}
    hovered:    u64 = Swag.U64.Max
}

// Both navigation modes occupy the same integrated outline lane and use its existing toggle.
impl Panel
{
    mtd createPageNavigation()
    {
        let outline = unwrap .outline
        let parent  = unwrap outline.parent
        let height  = themeCompactButtonSize(.themeMetrics())
        with .navigationMode = ComboBox.create(parent, {0, 0, 0, height}, flags: .Segmented)
        {
            .dockStyle = .Top
            .margin    = {0, 8, 8, 8}
            .sendToBack()
            .sigChanged += func|panel = me|(_, index) { panel.setNavigationMode(index == 0) }
        }

        with .pagesHeading = SectionLabel.create(parent, texts().ui_Thumbnails, {0, 0, 0, height})
        {
            .dockStyle = .Top
            .margin.y  = 8
            .sendToBack()
        }

        with .thumbnailScroll = Wnd.create'ScrollWnd(parent)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .updateFlags(.DisableHorizontal | .TransparentBars)
        }
        with .gallery = .thumbnailScroll.createView'PageGallery()
        {
            .panel           = me
            .focusPolicy     = .Tab
            .backgroundStyle = .Transparent
        }

        .translateNavigation()
        .setNavigationMode(true)
        outline.toggle.sigCheckedChanged += func|panel = me|(button)
        {
            if button.isChecked and panel.pagesSelected do
                panel.gallery.revealCurrentPage()
        }
    }

    mtd translateNavigation()
    {
        .pagesHeading.setText(texts().ui_Thumbnails)
        .navigationMode.clear()
        .navigationMode.addItem(texts().ui_Thumbnails)
        .navigationMode.addItem(texts().ui_Bookmarks)
        .navigationMode.setSelectedIndex(.pagesSelected ? 0 : 1, notify: false)
    }

    mtd setNavigationMode(pages: bool)
    {
        .pagesSelected = pages or .bookmarks.isEmpty()
        .navigationMode.setSelectedIndex(.pagesSelected ? 0 : 1, notify: false)
        .navigationMode.show(not .bookmarks.isEmpty())
        .pagesHeading.show(.bookmarks.isEmpty())
        .outline!.section.hide()
        .outline.show(not .pagesSelected)
        .thumbnailScroll.show(.pagesSelected)
        .outline.parent!.applyLayout()
        if .pagesSelected and .thumbnailScroll.isVisible() do
            .gallery.revealCurrentPage()
    }

    mtd openPages()
    {
        .setNavigationMode(true)
        let toggle = .outline!.toggle
        if not toggle.isChecked
        {
            toggle.setChecked(true)
            toggle.sigCheckedChanged.call(toggle)
        }
    }

    mtd clearThumbnails()
    {
        for &texture in .previewTextures where texture.isValid() do
            .app().renderer.removeTexture(texture)
        .previewTextures.clear()
    }

    mtd requestThumbnails()
    {
        if .thumbnailTask.isPending() or not .gallery.isVisible() do
            return
        let range = .gallery.visibleRange()
        if range.first == range.end or
           (range.first >= .thumbnailStart and range.end <= .thumbnailStart + .previewTextures.count) do
            return
        let first = range.first - Math.min(range.first, .gallery.columns)
        let end   = Math.min(.pdfView.pageCount(), range.end + .gallery.columns)
        .thumbnailTask.submit(func|panel = me, first, end|()->ThumbnailBatch =>
                                  loadThumbnailBatch(panel.fileName.toString(), first, end),
                              me.taskNotifier(&.thumbnailTask))
    }

    mtd installThumbnails(batch: *ThumbnailBatch)
    {
        .clearThumbnails()
        .thumbnailStart = batch.first
        for &image in batch.images do
            .previewTextures.add(image.isValid() ? .app().renderer.addImage(image) : Texture{})
        .gallery.invalidate()
    }
}

impl PageGallery
{
    mtd refreshLayout()
    {
        if .panel == null do
            return
        // Keep the page being browsed in view even when reflow changes its row.
        let topRow     = .scrollPos.y / .cell.y
        let anchor     = cast(u64, topRow) * .columns
        let fraction   = topRow - Math.floor(topRow)
        let oldColumns = .columns
        let oldHeight  = .cell.y
        let width      = Math.max(.position.width, 1)
        .columns   = Math.max(cast(u64, width / 118), 1)
        .cell.x    = width / cast(f32, .columns)
        .cell.y    = Math.clamp(Math.min(.cell.x * 1.35, .position.height * 0.55), 72, 192)
        let rows   = (.panel.pdfView.pageCount() + .columns - 1) / .columns
        .panel.thumbnailScroll.setScrollSize(0, cast(f32, rows) * .cell.y)
        if oldColumns != .columns or oldHeight != .cell.y do
            .panel.thumbnailScroll.setScrollPos(0, (cast(f32, anchor / .columns) + fraction) * .cell.y)
        .invalidate()
    }

    mtd visibleRange()->{first: u64, end: u64}
    {
        let count = .panel.pdfView.pageCount()
        let first = cast(u64, Math.max(0.0, .scrollPos.y) / .cell.y) * .columns
        let end   = cast(u64, Math.ceil((.scrollPos.y + .position.height) / .cell.y)) * .columns
        return {Math.min(first, count), Math.min(end, count)}
    }

    mtd cellRect(index: u64)->Math.Rectangle
        => {cast(f32, index % .columns) * .cell.x, cast(f32, index / .columns) * .cell.y, .cell.x, .cell.y}

    mtd revealCurrentPage()
    {
        .refreshLayout()
        let tile = .cellRect(.panel.pdfView.pageIndex)
        if tile.y < .scrollPos.y do
            .panel.thumbnailScroll.setScrollPos(0, tile.y)
        elif tile.bottom() > .scrollPos.y + .position.height do
            .panel.thumbnailScroll.setScrollPos(0, tile.bottom() - .position.height)
        .panel.requestThumbnails()
    }

    mtd choose(index: u64)
    {
        if index >= .panel.pdfView.pageCount() do
            return
        if index == .panel.pdfView.pageIndex
        {
            .revealCurrentPage()
            return
        }
        .panel.history.visit(.panel.pdfView.readingPosition())
        .panel.pdfView.showPage(index)
    }

    mtd paintPage(painter: *Painter, index: u64)
    {
        let tile   = .cellRect(index)
        let colors = .themeColors()
        let font   = unwrap .font().regular
        let label  = .panel.pageLabelOf(index)
        let text   = label.count ? String.from(label) : Format.toString("%", index + 1)
        let size   = Painter.measureString(text, font)
        let space  = Math.Point{Math.max(1.0, tile.width - 20), Math.max(1.0, tile.height - size.height - 20)}
        var texture: Texture
        if index >= .panel.thumbnailStart and index - .panel.thumbnailStart < .panel.previewTextures.count do
            texture = .panel.previewTextures[index - .panel.thumbnailStart]
        let aspect = texture.isValid() ? cast(f32, texture.width) / cast(f32, texture.height) : 0.71'f32
        let width  = Math.min(space.x, space.y * aspect)
        let height = width / aspect
        let paper  = Math.Rectangle{tile.horzCenter() - width / 2, tile.y + 8 + (space.y - height) / 2, width, height}
        if texture.isValid() do
            painter.fillRect(paper, Brush.createTexture(texture))
        else do
            painter.fillRect(paper, colors.faintText.withAlphaF32(0.12))
        let selected = index == .panel.pdfView.pageIndex
        let edge     = selected ? colors.arc : colors.faintText.withAlphaF32(index == .hovered ? 0.8 : 0.22)
        painter.drawRect(paper, edge, selected ? 2 : 1)
        if selected and .hasVisibleFocus()
        {
            var focus = paper
            focus.inflate(3)
            painter.drawRect(focus, colors.arc)
        }
        painter.pushClippingRect(tile)
        painter.drawString(Math.max(tile.x + 4, tile.horzCenter() - size.width / 2), font.opticalLineTop(tile.bottom() - size.height / 2 - 5),
                           text, font, selected ? colors.arc : colors.softText)
        painter.popClippingRect()
    }
}

impl IWnd for PageGallery
{
    mtd impl onResizeEvent(_: *ResizeEvent) => .refreshLayout()

    mtd impl onPaint(evt: *PaintEvent)
    {
        let range = .visibleRange()
        for index in range.first until range.end do
            .paintPage(evt.paintContext.painter, index)
        .panel.requestThumbnails()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos   = .surfaceToLocal(evt.surfacePos) + .scrollPos
        let index = pos.x >= 0 and pos.x < .position.width and pos.y >= 0 ?
                        cast(u64, pos.y / .cell.y) * .columns + cast(u64, pos.x / .cell.x) : Swag.U64.Max
        switch evt.kind
        {
        case .Move, .Enter, .Leave:
            let hovered = evt.kind == .Leave ? Swag.U64.Max : index
            if .hovered != hovered
            {
                .hovered = hovered
                .invalidate()
            }
        case .Pressed where evt.button == .Left:
            .setFocus()
            .choose(index)
        default:
            evt.accepted = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        let count = .panel.pdfView.pageCount()
        if evt.kind != .Pressed or evt.modifiers != .None or not count
        {
            evt.accepted = false
            return
        }
        let index = .panel.pdfView.pageIndex
        let step  = Math.max(cast(u64, .position.height / .cell.y), 1) * .columns
        switch evt.key
        {
        case .Left:  .choose(index - Math.min(index, 1))
        case .Right: .choose(Math.min(index + 1, count - 1))
        case .Up:    .choose(index - Math.min(index, .columns))
        case .Down:  .choose(Math.min(index + .columns, count - 1))
        case .PageUp:   .choose(index - Math.min(index, step))
        case .PageDown: .choose(Math.min(index + step, count - 1))
        case .Home:  .choose(0)
        case .End:   .choose(count - 1)
        default:     evt.accepted = false
        }
    }
}
