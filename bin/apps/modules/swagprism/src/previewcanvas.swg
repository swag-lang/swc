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
    mtd frameRect()->Math.Rectangle
    {
        let client = .paddedClientRect()
        let scale  = Math.min(client.width / Pipeline.FrameChannel.Width, client.height / Pipeline.FrameChannel.Height)
        let width  = Pipeline.FrameChannel.Width * scale
        let height = Pipeline.FrameChannel.Height * scale
        return {client.horzCenter() - width / 2, client.vertCenter() - height / 2, width, height}
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
            evt.paintContext.painter.drawTexture(.frameRect(), .texture, .themeColors().imageRect_Fg)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Released or not .texture.isValid() do
            return
        let point = .surfaceToLocal(evt.surfacePos)
        let rect  = .frameRect()
        if point.x < rect.x or point.y < rect.y or point.x >= rect.right() or point.y >= rect.bottom() do
            return
        .sigClick.call(Math.Point{(point.x - rect.x) * Pipeline.FrameChannel.Width / rect.width,
                                  (point.y - rect.y) * Pipeline.FrameChannel.Height / rect.height})
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .texture.isValid() do
            .app().renderer.removeTexture(&.texture)
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
