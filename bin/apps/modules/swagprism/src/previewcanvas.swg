#global internal

using Core, Gui, Pixel

// Fits the live frame without changing its aspect ratio and maps clicks back to its pixels.
struct PreviewCanvas
{
    using wnd: Wnd
    texture:   Texture
    sigClick:  SigArray'func||(Math.Point)
}

impl PreviewCanvas
{
    // The largest rectangle with the aspect of a frame, at the top of the canvas and centered
    // across it.
    mtd frameRect()->Math.Rectangle
    {
        let client      = .paddedClientRect()
        let widthScale  = client.width / Pipeline.FrameChannel.Width
        let heightScale = client.height / Pipeline.FrameChannel.Height
        let scale       = Math.min(widthScale, heightScale)
        let width       = Pipeline.FrameChannel.Width * scale
        let height      = Pipeline.FrameChannel.Height * scale
        let x           = client.horzCenter() - width / 2
        return Math.Rectangle{x, client.y, width, height}
    }

    mtd update(image: *Image)
    {
        if not .texture.isValid() do
            .texture = .app().renderer.addImage(image[])
        else do
            .app().renderer.updateTexture(.texture, image.pixels.storage())
        .invalidate()
    }
}

impl IWnd for PreviewCanvas
{
    // Draws the frame on the corner of a control, as a picture set in the page.
    mtd impl onPaint(evt: *PaintEvent)
    {
        if not .texture.isValid() do
            return

        let painter = evt.paintContext.painter
        let radius  = .themeMetrics().corner_Control
        var brush   = Brush.createTexture(.texture)
        brush.color = .themeColors().imageRect_Fg
        painter.setParams(.Antialiased)
        painter.fillRoundRect(.frameRect(), radius, radius, brush)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Released or not .texture.isValid() do
            return
        let point = .surfaceToLocal(evt.surfacePos)
        let rect  = .frameRect()
        if not rect.contains(point) do
            return

        let x = (point.x - rect.x) * Pipeline.FrameChannel.Width / rect.width
        let y = (point.y - rect.y) * Pipeline.FrameChannel.Height / rect.height
        .sigClick.call(Math.Point{x, y})
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .texture.isValid() do
            .app().renderer.removeTexture(&.texture)
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
