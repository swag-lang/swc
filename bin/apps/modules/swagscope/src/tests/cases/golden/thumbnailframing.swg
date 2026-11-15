#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Detailed subjects near the edge must stay visible when cover windows change aspect.
func attentionBoard(host: *Testing.HeadlessHost, posters: bool)->*ViewerWindow
{
    let window   = boardWindow(host, not posters, films: false, width: 880, height: 560)
    let explorer = unwrap window.explorer
    let names    = ["Landscape.mp4", "Portrait.jpg", "Portrait recording.webm"]
    for name, index in names
    {
        let width  = index == 0 ? 240 : 100
        let height = index == 0 ? 120 : 200
        var image  = Image.create(width, height, .RGB8)
        image.fill(Color.fromRgb(28, 32, 38))
        for y in (index == 0 ? 24 : 10) until (index == 0 ? 96 : 70)
        {
            for x in (index == 0 ? 160 : 32) until (index == 0 ? 216 : 68)
            {
                let pixel = image.pixels.storage() + cast(u64, (height - 1 - y) * image.rowStride + x * 3)
                pixel[0] = 220
                pixel[1] = cast(u8, (x + y) % 2 == 0 ? 156 : 136)
                pixel[2] = 104
            }
        }

        explorer.entries.add({name: name, path: name, attempted: true,
                              texture: host.app.renderer.addImage(&image),
                              framing: ThumbnailFraming.analyze(&image)})
    }

    explorer.forceBoard(true, posters ? .Posters : .Grid)
    showBoard(host, window, "Pictures", posters ? "Portraits" : "Smart framing")
    return window
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = attentionBoard(&host, false)
    let explorer = unwrap window.explorer
    let grid     = explorer.grid
    let picture  = grid.tileRect(1)
    let centre   = grid.localToSurface(picture.center())
    let image    = host.renderSettled(&host.surfaceWnd)
    let subject  = image.pixelColor(cast(s32, centre.x), cast(s32, centre.y))
    Swag.require(subject.r > 180 and subject.g > 100)
    Pixel.Testing.assertImageGolden(&image, "framing.grid.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = attentionBoard(&host, true)
    let image  = host.renderSettled(window)
    Pixel.Testing.assertImageGolden(&image, "framing.posters.encre")
}
