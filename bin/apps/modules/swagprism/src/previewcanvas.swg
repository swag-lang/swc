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
    // The largest rectangle with the aspect of a frame, centered in the canvas.
    mtd frameRect()->Math.Rectangle
    {
        let client      = .paddedClientRect()
        let widthScale  = client.width / Pipeline.FrameChannel.Width
        let heightScale = client.height / Pipeline.FrameChannel.Height
        let scale       = Math.min(widthScale, heightScale)
        let width       = Pipeline.FrameChannel.Width * scale
        let height      = Pipeline.FrameChannel.Height * scale
        let x           = client.horzCenter() - width / 2
        let y           = client.vertCenter() - height / 2
        return {x, y, width, height}
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
    mtd impl onPaint(evt: *PaintEvent)
    {
        if .texture.isValid() do
            evt.paintContext.painter.drawTexture(.frameRect(),
                                                 .texture,
                                                 .themeColors().imageRect_Fg)
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
