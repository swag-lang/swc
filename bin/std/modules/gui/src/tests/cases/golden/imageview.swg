#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

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
