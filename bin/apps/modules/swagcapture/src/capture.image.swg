// Keep one bounded preview per capture, including for the largest grid tiles on HiDPI.
private const PreviewWidth  = 768.0
private const PreviewHeight = 576.0

private func previewScale(width, height: s32)->f32 => Math.min(1.0, PreviewWidth / width, PreviewHeight / height)

// Prepares a standalone image or a recovered video frame without needing an editor or renderer.
func resizeLibraryPreview(image: *Image)
{
    let scale = previewScale(image.width, image.height)
    if scale < 1 do
        image.resize(Math.max(1, cast(s32, image.width * scale)),
                     Math.max(1, cast(s32, image.height * scale)),
                     .CatmullRom)
}

impl Capture
{
    mtd computePreview()
    {
        if not .editView do
            return

        .previewBytes.clear()
        .preview = .toImage(previewScale(.width, .height))
        .changed = true
    }

    // Decodes the retained SCC thumbnail on demand. Full loads already carry
    // pixels, while library-only SCC loads keep the much smaller PNG bytes between paints.
    mtd materializePreview() fail
    {
        if .preview.isValid() or .previewBytes.isEmpty() do
            return
        .preview = try Image.decode("preview.png", .previewBytes.toSlice())
    }

    // Renders the capture, or only its selected forms, into an image at `zoom`. Pixel selections
    // are working state and are left out.
    mtd toImage(zoom: f32 = 1, onlySel = false)->Image
    {
        var result: #returntype

        let rect    = Math.Rectangle{width: .width * zoom, height: .height * zoom}
        let render  = .editView!.app().renderer
        var painter = Pixel.Painter.create(render)
        let surface = unwrap .editView.surface
        render.begin(surface.renderingContext())
        painter.begin()

        let width  = Math.max(1, cast(s32, rect.width))
        let height = Math.max(1, cast(s32, rect.height))
        var layer: Layer
        layer.begin(&painter, {width: width, height: height, paintAlpha: false, clearColor: Color.fromArgb(Argb.White)})

        .paintBackImage(&painter, 0, 0, zoom)
        with painter
        {
            .setColorMaskColor()
            .setParams(.Antialiased)
        }

        if onlySel
        {
            for sel in .selection
            {
                let f = .forms[sel]
                if f.subKind == .PixSel do
                    continue
                paintForm(&painter, {}, rect, f, zoom, snapMode: true)
            }
        }
        else
        {
            for f in .forms where .isFormShown(f)
            {
                let b: *BaseForm = f
                if b.subKind == .PixSel do
                    continue
                paintForm(&painter, {}, rect, f, zoom, snapMode: true)
            }
        }

        layer.end()
        painter.end()

        catch render.draw(&painter)
        {
            render.end()
            layer.release()
            return {}
        }

        render.end()

        let rt     = unwrap layer.contentTarget
        var buffer = render.readTexturePixels(rt.colorBuffer, .BGRA8)
        result = Image.create(rt.colorBuffer.width, rt.colorBuffer.height, .BGRA8, buffer.toSlice())
        result.crop(0, 0, width, height)
        render.releaseRenderTarget(rt)

        return result
    }
}
