#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A movie decoded away from the widget is published by ownership exchange only.

// A still image starts fitted, supports explicit zoom, and releases its renderer texture cleanly.

// Exchanging a picture keeps the texture and the view, and hands the previous pixels back.

// A one-shot decode can hand its storage to the view without allocating a second pixel buffer.

// Rotation and reflection are paint-time view operations: the source keeps its dimensions and
// bytes while the asymmetric pattern proves that the composed transform reaches the renderer.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 160)

    let pixels: [24] u8 = [
        255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255,
        255, 255, 0, 255, 255, 0, 255, 255, 0, 255, 255, 255]
    let source   = Image.create(3, 2, .RGBA8, pixels)
    let original = ImageView.create(&host.root, {0, 0, 130, 160})
    original.setImage(source)
    original.setDisplaySize(90, 60)
    original.actualSize()
    let view = ImageView.create(&host.root, {130, 0, 130, 160})
    view.setImage(source)
    view.setDisplaySize(90, 60)
    view.actualSize()
    view.rotateClockwise()
    view.mirrorHorizontally()

    Swag.assert(view.image.width == 3 and view.image.height == 2)
    Swag.assert(view.rotationQuarterTurns == 3 and view.isMirrored)
    var rendered = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&rendered, "imageview.transform")
}

// Counts the pixels of one row that sit between the two plateaus of an opaque red-on-white
// picture, which is how wide the edges crossing that row are drawn.
private func edgeSpread(image: *Image, row: s32)->s32
{
    var result = 0's32
    for x in image.width
    {
        let green = cast(s32, image.pixelColor(x, row).g)
        if green > 8 and green < 247 do
            result += 1
    }

    return result
}

// A vector document is drawn at the scale the view shows it at, so a magnified drawing is drawn
// again rather than magnified: its edges stay a pixel wide however far the view zooms in.
//
// The same document rasterized once at its view-box size and shown through the picture path is
// the control: there the zoom magnifies pixels, and every edge is spread over the zoom factor.
// The document is opaque and covers its whole view box, so the only pixels between the two
// plateaus of the measured row are the two edges of the disc.

// A video frame reaches the view as planes: the texture is kept across frames, the geometry comes
// from the picture even though the view holds no image, and the next size starts a new texture.

// A picture whose samples are not square is laid out and fitted with the size it is shown at,
// while the storage it was given keeps every column it holds.
