#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Read and navigate bytes beyond 4 GiB without keeping the gap in memory.
#[Swag.TestTag("stress")]
#test
{
    let file = Testing.tempFilePath("scope-hex-sparse-", ".bin")
    defer discard catch File.delete(file)
    const FarOffset = 0x1_0000_0100'u64
    scope
    {
        var stream = expect File.open(file, .CreateNew, .ReadWrite, .Zero)
        expect stream.writeAll([0x41'u8, 0x42'u8])
        expect stream.seek(.Begin, FarOffset)
        expect stream.writeAll([0xDE'u8, 0xAD'u8, 0xBE'u8, 0xEF'u8])
        stream.close()
    }

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, file, 900, 560)
    let grid = view.grid
    Swag.require(grid.doc.fileSize == FarOffset + 4 and grid.offsetDigits == 16)
    Swag.require(grid.goToTypedOffset("0x100000100") and grid.caret == FarOffset)
    var image = host.render(view)
    Swag.require(image.isValid())
    Swag.require(grid.doc.byteAt(grid.caret) == 0xDE)
    Swag.require(grid.doc.window.count <= Hex.WindowSize)
    Swag.require(grid.doc.windowStart <= FarOffset and
                 grid.doc.windowStart + grid.doc.window.count > 0x1_0000_0000)

    host.focus(grid)
    host.keyPress(.End, .Control)
    Swag.require(grid.caret == FarOffset + 3 and grid.doc.byteAt(grid.caret) == 0xEF)
    image = host.render(view)
    Swag.require(image.isValid())
    Swag.require(grid.scroll.scrollSize.y <= Hex.ScrollSpan)
}
