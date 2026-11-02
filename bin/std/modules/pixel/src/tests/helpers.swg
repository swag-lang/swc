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

func nnBytes(bytes: const [..] u8?)->const [..] u8 => unwrap bytes

func makeImage(width, height: s32, pf: PixelFormat, buffer: const [..] u8)->Image
{
    let expectedSize = cast(u64, (width * height * cast(s32, (pf.bitsPerPixel() >> 3))))
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

// Signed area of one closed clipping contour, positive for one winding direction and negative for
// the other, so a solution's holes subtract themselves from its outers.
func contourArea(contour: Pixel.Clipper.ClipperPath)->f64
{
    let count = contour.count
    if count < 3 do
        return 0

    var total = 0.0'f64
    var prev  = count - 1
    for i in count
    {
        total += cast(f64, (contour[prev].x + contour[i].x)) * cast(f64, (contour[prev].y - contour[i].y))
        prev  = i
    }

    return total * 0.5
}

// Area of the region a clipping solution covers, whatever orientation the solver gave its contours.
func solutionArea(paths: Pixel.Clipper.ClipperPaths)->f64
{
    var total = 0.0'f64
    for path in paths do
        total += contourArea(path)
    return Math.abs(total)
}

// White masks recover coverage from one black matte. An invisible colored shape selects the
// two-matte reference without changing its pixels, including clipped translucent overlaps.
func assertSvgWhiteMaskRaster(renderer: IRenderer, sampleTileSide: s32)
{
    const Content = """
        <defs><clipPath id='c'><circle cx='46' cy='38' r='34'/></clipPath></defs>
        <g clip-path='url(#c)' fill='white' stroke='white' stroke-width='1.4'>
          <rect x='8' y='5' width='52' height='48' rx='5' fill-opacity='0.3'/>
          <circle cx='54' cy='40' r='25' fill-opacity='0.6'/>
          <path d='M4 68L82 7M9 10L84 64' fill='none' stroke-opacity='0.4'/>
        </g>
        """
    let source          = Format.toString("<svg width='91' height='75'>%</svg>", Content)
    let referenceSource = Format.toString("<svg width='91' height='75'>%<rect width='1' height='1' fill='red' fill-opacity='0'/></svg>", Content)
    let drawing         = expect Svg.Drawing.parse(source.toString())
    let reference       = expect Svg.Drawing.parse(referenceSource.toString())
    for samples in [1'u8, 2'u8, 4'u8, 8'u8]
    {
        let image    = drawing.rasterizeWithSampleTileSide(renderer, 91, 75, samples, sampleTileSide)
        let expected = reference.rasterizeWithSampleTileSide(renderer, 91, 75, samples, sampleTileSide)
        for value, index in image.pixels do
            Swag.assert(value == expected.pixels[index], Format.toString("SVG white mask differs at sample count %, byte %: got %, expected %", samples, index, value, expected.pixels[index]))
    }
}

// Reuse the existing font fixture. The second copy declares bold in head.macStyle,
// making index selection observable without adding another font binary.
func makeTypeFaceCollection()->Array'u8
{
    func read32(bytes: *Array'u8, offset: u64)->u32 => cast(u32, bytes[offset]) << 24 |
                                                    cast(u32, bytes[offset + 1]) << 16 |
                                                    cast(u32, bytes[offset + 2]) << 8 |
                                                    bytes[offset + 3]
    func write32(bytes: *Array'u8, offset: u64, value: u32)
    {
        for index in 4 do
            bytes[offset + index] = cast(u8, (value >> ((3 - index) * 8)) & 255)
    }

    let source = expect File.readAllBytes(getTestDataPath("segoeui.ttf"))
    var bytes: Array'u8
    bytes.resize(20)
    write32(&bytes, 0, 0x74746366)
    write32(&bytes, 4, 0x00010000)
    write32(&bytes, 8, 2)
    for index in 2
    {
        bytes.resize((bytes.count + 3) & ~3'u64)
        let offset = cast(u32, bytes.count)
        write32(&bytes, 12 + index * 4, offset)
        bytes.add(source.toSlice())
        let tables = cast(u32, bytes[offset + 4]) << 8 | bytes[offset + 5]
        var foundHead = false
        for table in tables
        {
            let record = cast(u64, offset) + 12 + table * 16
            let target = read32(&bytes, record + 8) + offset
            write32(&bytes, record + 8, target)
            if read32(&bytes, record) == 0x68656164
            {
                bytes[target + 44] = 0
                bytes[target + 45] = cast(u8, index)
                foundHead = true
            }
        }
        Swag.assert(foundHead)
    }
    return bytes
}
