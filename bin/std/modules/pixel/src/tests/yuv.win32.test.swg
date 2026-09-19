#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Win32

// A tightly packed final chroma row ends at an inaccessible page. Sixteen luma samples
// consume only eight chroma bytes, including when the visible crop is unaligned.
#test
{
    let pages = cast([*] u8) VirtualAlloc(null, 8192, MEM_RESERVE, PAGE_READWRITE)!
    defer discard VirtualFree(pages, 0, MEM_RELEASE)
    let committed = VirtualAlloc(pages, 4096, MEM_COMMIT, PAGE_READWRITE)
    Swag.assert(committed != null)
    for width in 16's32 until 33
    {
        let chromaWidth = cast(u64) ((width + 1) / 2)
        let chroma      = pages + 4096 - chromaWidth
        for x in chromaWidth do
            chroma[x] = cast(u8) (70 + x * 9)
        var luma: [64] u8
        for x in cast(u64) width * 2 do
            luma[x] = cast(u8) ((x * 11) & 255)
        let view  = YuvPlanarView{luma: &luma, chromaB: chroma, chromaR: chroma, lumaStride: cast(u64) width, chromaStride: chromaWidth, width: width, height: 2}
        var image = Image.create(width, 2, .RGB8)
        view.convertRowsToRgb(&image, 0, 2)
        for y in 2's32
        {
            for x in width do
                Swag.assert(image.pixelColor(x, y) == expectedPlanarColor(luma[y * width + x], chroma[x / 2], chroma[x / 2]))
        }
    }
}
