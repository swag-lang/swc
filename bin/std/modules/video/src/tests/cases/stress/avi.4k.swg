#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

const Width  = 3840
const Height = 2160

// A tiled picture with distinct channels and asymmetric rows.
func avi4kPicture()->Image
{
    const Colors: [4] [3] u8 = [[140'u8, 255, 0], [16'u8, 49, 66], [231'u8, 82, 123], [33'u8, 189, 214]]
    let result = Image.create(Width, Height, .RGB8)
    let pixels = result.pixels.storage()
    for y in Height
    {
        for x in Width
        {
            let color = Colors[(x / 31 + y / 17) & 3]
            let pixel = pixels + cast(u64, (y * Width + x) * 3)
            pixel[0] = color[0]
            pixel[1] = color[1]
            pixel[2] = color[2]
        }
    }

    return result
}

// Wraps one test payload in a minimal AVI with its bitmap format and no index.
func writeAvi4kFrame(path: string, pixels: const [..] u8, bitCount: u16, topDown: bool, compression: u32 = Bmp.BI_RGB)
{
    const StreamListSize = Avi.FourCcSize + 2 * Avi.ChunkHeaderSize + #sizeof(Avi.StreamHeader) + #sizeof(Bmp.Header)
    const HeaderListSize = Avi.FourCcSize + 2 * Avi.ChunkHeaderSize + #sizeof(Avi.MainHeader) + StreamListSize
    let movieListSize = Avi.FourCcSize + Avi.ChunkHeaderSize + pixels.count + (pixels.count & 1)
    let riffSize      = Avi.FourCcSize + 2 * Avi.ChunkHeaderSize + HeaderListSize + movieListSize

    var sink = expect ByteSink.createFile(path)
    expect sink.writeText("RIFF")
    expect sink.writeLittleEndian(cast(u32, riffSize))
    expect sink.writeText("AVI LIST")
    expect sink.writeLittleEndian(cast(u32, HeaderListSize))
    expect sink.writeText("hdrlavih")
    expect sink.writeLittleEndian(cast(u32, #sizeof(Avi.MainHeader)))
    expect sink.writeNative(Avi.MainHeader{totalFrames: 1, streams: 1, width: Width, height: Height})

    expect sink.writeText("LIST")
    expect sink.writeLittleEndian(cast(u32, StreamListSize))
    expect sink.writeText("strlstrh")
    expect sink.writeLittleEndian(cast(u32, #sizeof(Avi.StreamHeader)))
    expect sink.writeNative(Avi.StreamHeader{kind: Avi.VideoStreamId, handler: compression, scale: 1, rate: 30, length: 1})
    expect sink.writeText("strf")
    expect sink.writeLittleEndian(cast(u32, #sizeof(Bmp.Header)))
    expect sink.writeNative(Bmp.Header{biSize: cast(u32, #sizeof(Bmp.Header)), biWidth: Width, biHeight: topDown ? -Height : Height,
                                       biPlanes: 1, biBitCount: bitCount, biCompression: compression, biSizeImage: cast(u32, pixels.count)})

    expect sink.writeText("LIST")
    expect sink.writeLittleEndian(cast(u32, movieListSize))
    expect sink.writeText(compression == Bmp.BI_RGB ? "movi00db" : "movi00dc")
    expect sink.writeLittleEndian(cast(u32, pixels.count))
    expect sink.write(pixels)
    if pixels.count & 1 do
        expect sink.writeByte(0)
    expect sink.close()
}

func assertAvi4kFrame(path: string, reference: const *Image)
{
    func check(reader: *Reader, reference: const *Image)
    {
        Swag.require(reader.frameCount() == 1 and reader.width() == Width and reader.height() == Height)
        var decoded: Image
        expect reader.decodeFrameInto(&decoded, 0)
        Swag.require(decoded.pixelFormat == .RGB8 and decoded.isValid())
        Swag.require(Slice.equals(decoded.pixels.toSlice(), reference.pixels.toSlice()))

        let storage = decoded.pixels.buffer
        expect reader.decodeFrameInto(&decoded, 0)
        Swag.require(decoded.pixels.buffer == storage)
        Swag.require(Slice.equals(decoded.pixels.toSlice(), reference.pixels.toSlice()))
    }

    var file = expect Reader.open(path)
    check(&file, reference)

    let bytes  = expect File.readAllBytes(path)
    var memory = expect Reader.openMemory(path, bytes.toSlice())
    check(&memory, reference)
}

// Check every output byte for all three packed depths and both bitmap row orders.
#[Swag.TestTag("stress")]
#test
{
    const Depths:    [3] u16 = [16, 24, 32]
    const Expanded5: [32] u8 = [0'u8, 8, 16, 24, 33, 41, 49, 57, 66, 74, 82, 90, 99, 107, 115, 123,
                                132, 140, 148, 156, 165, 173, 181, 189, 198, 206, 214, 222, 231, 239, 247, 255]
    for bitCount in Depths
    {
        let reference  = bitCount == 16 ? Image.create(Width, Height, .RGB8) : avi4kPicture()
        let topDown    = bitCount == 24
        let pixelBytes = cast(u64, bitCount / 8)
        let rowBytes   = Width * pixelBytes
        var payload: Array'u8
        payload.resize(Height * rowBytes)

        for y in Height
        {
            let sourceY = topDown ? Height - 1 - y : y
            var source  = reference.pixels.storage() + cast(u64, sourceY) * reference.rowStride
            var dest    = payload.storage() + cast(u64, y) * rowBytes
            for x in Width
            {
                if bitCount == 16
                {
                    // Exercise every packed word, including the unused high bit.
                    let packed = cast(u32, (y * Width + x) & 0xFFFF)
                    dest[0]   = cast(u8, packed & 255)
                    dest[1]   = cast(u8, packed >> 8)
                    source[0] = Expanded5[(packed >> 10) & 31]
                    source[1] = Expanded5[(packed >> 5) & 31]
                    source[2] = Expanded5[packed & 31]
                }
                else
                {
                    dest[0] = source[2]
                    dest[1] = source[1]
                    dest[2] = source[0]
                    if bitCount == 32 do
                        dest[3] = cast(u8, (x + y) & 255)
                }

                source += 3
                dest   += pixelBytes
            }
        }

        let path = videoTempPath("avi-raw-4k", "avi")
        defer discard catch File.delete(path)
        writeAvi4kFrame(path, payload.toSlice(), bitCount, topDown)
        assertAvi4kFrame(path, &reference)
    }
}

// A JPEG embedded in AVI must match the same JPEG decoded directly through Pixel.
#[Swag.TestTag("stress")]
#test
{
    let picture = avi4kPicture()
    let jpeg    = expect picture.encodeToBytes(".jpg")
    var decoded = expect Image.decode(".jpg", jpeg.toSlice())
    decoded.convertTo(.RGB8)

    let path = videoTempPath("avi-mjpeg-4k", "avi")
    defer discard catch File.delete(path)
    writeAvi4kFrame(path, jpeg.toSlice(), 24, false, Avi.MotionJpegIds[0])
    assertAvi4kFrame(path, &decoded)
}

// A moving box crosses the probes at different display ranks, including bidirectional frames.
#[Swag.TestTag("stress")]
#test
{
    struct Probe
    {
        x, y: s32
        firstRed, lastRed: u64
    }

    const Probes: [7] Probe = [
        {115,       240,        0, 1},
        {128,       240,        0, 3},
        {144,       240,        0, 5},
        {200,       244,        1, 5},
        {217,       248,        3, 5},
        {233,       250,        5, 5},
        {Width - 1, Height - 1, 6, 6}]
    const Ranks = [0'u64, 1, 2, 3, 4, 5, 3, 1, 5, 0]

    var reader = expect Reader.open(videoFixturePath("ffmpeg-mpeg4-motion-4k.avi"))
    Swag.require(reader.frameCount() == 6 and reader.hasPlanarFrames())
    var frame: PlanarFrame
    for rank in Ranks
    {
        expect reader.decodeFramePlanesInto(&frame, rank)
        Swag.require(frame.width == Width and frame.height == Height)
        for probe in Probes
        {
            let red    = rank >= probe.firstRed and rank <= probe.lastRed
            let luma   = probe.y * frame.strideLuma + probe.x
            let chroma = (probe.y / 2) * frame.strideChroma + probe.x / 2
            Swag.require(Math.abs(cast(s32, frame.luma[luma]) - (red ? 81 : 126)) <= 3)
            Swag.require(Math.abs(cast(s32, frame.chromaB[chroma]) - (red ? 90 : 128)) <= 3)
            Swag.require(Math.abs(cast(s32, frame.chromaR[chroma]) - (red ? 240 : 128)) <= 3)
        }
    }

    // Packed output must keep queued planes usable when a later seek asks for planar output.
    var expected, packed: Image
    for rank in [0'u64, 3, 2, 5]
    {
        expect reader.decodeFramePlanesInto(&frame, rank)
        frame.view().convertToRgb(&expected)
        expect reader.decodeFrameInto(&packed, rank)
        Swag.require(Slice.equals(packed.pixels.toSlice(), expected.pixels.toSlice()))
    }
}
