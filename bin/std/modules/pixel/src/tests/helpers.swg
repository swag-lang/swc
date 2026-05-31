#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func getTestDataPath(fileName: string, loc = #callerlocation)->string
{
    var path = Path.getDirectoryName(loc.fileName)
    path = Path.combine(path, "data")
    path = Path.combine(path, fileName)
    @assert(File.exists(path))
    return path
}

func makeTempBmpPath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_pixel_bmp_"
    name += GUID64.getRandom().getString()
    name += ".bmp"
    return Path.combine(tempDir.toString(), name.toString())
}

func makeTempTgaPath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_pixel_tga_"
    name += GUID64.getRandom().getString()
    name += ".tga"
    return Path.combine(tempDir.toString(), name.toString())
}

func makeTempPngPath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_pixel_png_"
    name += GUID64.getRandom().getString()
    name += ".png"
    return Path.combine(tempDir.toString(), name.toString())
}

func makeTempGifPath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_pixel_gif_"
    name += GUID64.getRandom().getString()
    name += ".gif"
    return Path.combine(tempDir.toString(), name.toString())
}

func makeImage(width, height: s32, pf: PixelFormat, buffer: const [..] u8)->Image
{
    let expectedSize = cast(u64) (width * height * cast(s32) (pf.bpp() >> 3))
    @assert(@countof(buffer) == expectedSize)
    return Image.create(width, height, pf, buffer)
}

func assertImage(img: Image, width, height: s32, pf: PixelFormat)
{
    @assert(img.isValid())
    @assert(img.width == width)
    @assert(img.height == height)
    @assert(img.pf == pf)
}

func assertPixel(img: Image, x, y: s32, expected: Color)
{
    let got = img.getPixelColor(x, y)
    @assert(got.r == expected.r)
    @assert(got.g == expected.g)
    @assert(got.b == expected.b)
    @assert(got.a == expected.a)
}

func assertPixel(img: Image, x, y: s32, argb: u32)
{
    assertPixel(img, x, y, Color.fromArgb(argb))
}
