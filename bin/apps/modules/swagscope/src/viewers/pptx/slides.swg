#global internal
#global namespace Viewers.Pptx

using Core, Gui, Pixel

impl Panel
{
    mtd createSlideNavigation()
    {
        .navigation.selectPage      = func|view = me|(index) { view.showSlide(index) }
        .navigation.preparePreviews = func|view = me|() { view.trimPreviews() }
        .navigation.previewAspect   = func|view = me|(_)->f32 => view.navigation.slideAspect
        .navigation.paintPreview    = func|view = me|(context, index, paper) { view.paintSlidePreview(context, index, paper) }
        .navigation.createPageNavigation(.outline, texts().ui_Thumbnails, texts().ui_Titles)
    }

    mtd clearPreviews()
    {
        for &layer in .previews where layer.contentTarget do
            layer.release()
    }

    mtd trimPreviews()
    {
        let range = .gallery.visibleRange()
        for &layer, index in .previews where layer.contentTarget and (index < range.first or index >= range.end) do
            layer.release()
    }

    // Record the same slide renderer as the reading view at a legible layout size. The gallery
    // scales its cached image, so a thumbnail has no nested scroll area, links or keyboard focus.
    mtd paintSlidePreview(context: *PaintContext, index: u64, paper: Math.Rectangle)
    {
        let layer = &.previews[index]
        if not layer.contentTarget or layer.deviceScale != context.painter.contentScale()
        {
            let page   = &.presentation.slides[index]
            let scale  = 384.0 / Math.max(.presentation.width, .presentation.height)
            let width  = Math.max(1, cast(s32, Math.round(.presentation.width * scale)))
            let height = Math.max(1, cast(s32, Math.round(.presentation.height * scale)))
            var style = HtmlStyle.theme()
            style.followTheme = page.simplified
            let preview = HtmlView.createText(me, page.canvasHtml(.presentation.width, .presentation.height), style)
            preview.hide()
            defer preview.destroy()
            preview.resize(cast(f32, width), cast(f32, height))
            preview.applyLayout()
            layer.begin(context.painter, {width: width, height: height})
            preview.paint(context)
            layer.end()
        }

        layer.draw({dstRect: paper, releaseAfterDraw: false})
    }
}
