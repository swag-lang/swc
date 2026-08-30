#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Returns the OWNED path: a 'string' view would dangle as soon as the intermediate
// 'Path.combine' results are dropped (caught by the owner-view escape analysis).
func getTestDataPath(fileName: string, loc = #callerlocation)->String
{
    let dir  = Path.directoryName(loc.fileName)
    var path = Path.combine(dir, "datas", fileName)
    Swag.assert(File.exists(path))
    return path
}

func makeTempImagePath(extension: string)->String
{
    let tempDir      = Env.getSpecialDirectory(.Temp)
    var name: String = "swag_pixel_"
    name += Guid64.random().toString()
    name += extension
    return Path.combine(tempDir.toString(), name.toString())
}

func makeTempBmpPath()->String  => makeTempImagePath(".bmp")
func makeTempTgaPath()->String  => makeTempImagePath(".tga")
func makeTempPngPath()->String  => makeTempImagePath(".png")
func makeTempGifPath()->String  => makeTempImagePath(".gif")
func makeTempTiffPath()->String => makeTempImagePath(".tif")
func makeTempIcoPath()->String  => makeTempImagePath(".ico")

// Copy a ConcatBuffer's bytes into an owning Array. ConcatBuffer cannot be
// returned by value safely (it owns linked buckets), so test builders that
// assemble bytes return an Array instead.
func cbToArray(cb: *ConcatBuffer)->Array'u8
{
    cb.makeLinear()
    var result: retval
    let s = cb.toSlice()
    result.resize(s.count)
    if s.count do
        Memory.copy(result.buffer, s.buffer, s.count)
    return result
}

func nnBytes(bytes: #null const [..] u8)->const [..] u8
{
    Swag.assert(bytes != null)
    return Swag.makeSlice(cast(const [*] u8) bytes.buffer!, bytes.count)
}

func loadTestTypeFace(fullname: string)->#null *TypeFace fail
{
    return try TypeFace.load(fullname)
}

func makeImage(width, height: s32, pf: PixelFormat, buffer: const [..] u8)->Image
{
    let expectedSize = cast(u64) (width * height * cast(s32) (pf.bitsPerPixel() >> 3))
    Swag.assert(buffer.count == expectedSize)
    return Image.create(width, height, pf, buffer)
}

func assertImage(img: Image, width, height: s32, pf: PixelFormat)
{
    Swag.assert(img.isValid())
    Swag.assert(img.width == width)
    Swag.assert(img.height == height)
    Swag.assert(img.pixelFormat == pf)
}

func assertPixel(img: Image, x, y: s32, expected: Color)
{
    let got = img.pixelColor(x, y)
    Swag.assert(got.r == expected.r)
    Swag.assert(got.g == expected.g)
    Swag.assert(got.b == expected.b)
    Swag.assert(got.a == expected.a)
}

func assertPixel(img: Image, x, y: s32, argb: u32)
{
    assertPixel(img, x, y, Color.fromArgb(argb))
}
