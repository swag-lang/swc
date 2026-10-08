impl Capture
{
    mtd computePreview()
    {
        if not .editView do
            return
        let zoom = Math.min(PreviewWidth / .width, PreviewHeight / .height)
        .previewBytes.clear()
        .preview = .toImage(zoom)
        .preview.applyKernel(.GaussianBlur3x3Light)
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
        var result: retval

        let rect    = Math.Rectangle{width: .width * zoom, height: .height * zoom}
        let render  = g_App.renderer
        var painter = Pixel.Painter.create(render)
        let surface = (.editView!.surface)!
        render.begin(surface.renderingContext())
        painter.begin()

        var layer: Layer
        layer.begin(&painter, {width: cast(s32, rect.width), height: cast(s32, rect.height), paintAlpha: false, clearColor: Color.fromArgb(Argb.White)})

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
                let b = assume cast(*BaseForm, f)
                if b.subKind == .PixSel do
                    continue
                paintForm(&painter, {}, rect, f, zoom, snapMode: true)
            }
        }
        else
        {
            for f in .forms
            {
                let b = assume cast(*BaseForm, f)
                if b.subKind == .PixSel do
                    continue
                paintForm(&painter, {}, rect, f, zoom, snapMode: true)
            }
        }

        layer.end()
        painter.end()

        render.draw(&painter)
        render.end()

        let rt     = layer.contentTarget!
        var buffer = render.readTexturePixels(rt.colorBuffer, .BGRA8)
        result = Image.create(rt.colorBuffer.width, rt.colorBuffer.height, .BGRA8, buffer.toSlice())
        result.crop(0, 0, cast(s32, rect.width), cast(s32, rect.height))
        render.releaseRenderTarget(rt)

        return result
    }
}
