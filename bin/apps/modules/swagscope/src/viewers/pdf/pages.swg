#global internal
#global namespace Viewers.PdfDocument

using Core, Gui, Pixel

impl Panel
{
    mtd createPdfNavigation()
    {
        .navigation.selectPage = func|panel = me|(index)
        {
            panel.history.visit(panel.pdfView.readingPosition())
            panel.pdfView.showPage(index)
        }
        .navigation.labelOf = func|panel = me|(index)->string => panel.pageLabelOf(index)
        .navigation.preparePreviews = func|panel = me|() { panel.requestThumbnails() }
        .navigation.previewAspect = func|panel = me|(index)->f32
        {
            let texture = panel.pageTexture(index)
            return texture.isValid() ? cast(f32, texture.width) / cast(f32, texture.height) : 0.71
        }
        .navigation.paintPreview = func|panel = me|(context, index, paper)
        {
            let texture = panel.pageTexture(index)
            if texture.isValid() do
                context.painter.fillRect(paper, Brush.createTexture(texture))
            else do
                context.painter.fillRect(paper, panel.gallery.themeColors().faintText.withAlphaF32(0.12))
        }
        .navigation.createPageNavigation(unwrap .outline, texts().ui_Thumbnails, texts().ui_Bookmarks)
    }

    mtd pageTexture(index: u64)->Texture
    {
        if index >= .thumbnailStart and index - .thumbnailStart < .previewTextures.count do
            return .previewTextures[index - .thumbnailStart]
        return {}
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
