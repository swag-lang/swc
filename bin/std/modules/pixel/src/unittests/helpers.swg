#global #if #command == Swag.CompilerCommand.Test
#global #[Swag.ExplicitNullability]
using Swag, Core

// Returns the OWNED path: a '#nonull string' view would dangle as soon as the intermediate
// 'Path.combine' results are dropped (caught by the owner-view escape analysis).
func getTestDataPath(fileName: #nonull string, loc = #callerlocation)->String
{
    let dir  = Path.getDirectoryName(loc.fileName)
    var path = Path.combine(dir, "datas", fileName)
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

func makeTempTiffPath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_pixel_tiff_"
    name += GUID64.getRandom().getString()
    name += ".tif"
    return Path.combine(tempDir.toString(), name.toString())
}

func makeTempIcoPath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_pixel_ico_"
    name += GUID64.getRandom().getString()
    name += ".ico"
    return Path.combine(tempDir.toString(), name.toString())
}

// Copy a ConcatBuffer's bytes into an owning Array. ConcatBuffer cannot be
// returned by value safely (it owns linked buckets), so test builders that
// assemble bytes return an Array instead.
func cbToArray(cb: #nonull *ConcatBuffer)->Array'u8
{
    cb.makeLinear()
    var result: retval
    let s = cb.toSlice()
    result.resize(@countof(s))
    if @countof(s) do
        Memory.copy(result.buffer, @dataof(s), @countof(s))
    return result
}

func nnBytes(bytes: #null [..] u8)->#nonull const [..] u8
{
    @assert(bytes != null)
    return @mkslice(cast(#nonull [*] u8) (assume @dataof(bytes)), @countof(bytes))
}

func loadTestTypeFace(outFace: #nonull *#nonull *TypeFace, fullname: #nonull string) throw
{
    dref outFace = try TypeFace.load(fullname)
}

func makeImage(width, height: s32, pf: PixelFormat, buffer: #nonull const [..] u8)->Image
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
