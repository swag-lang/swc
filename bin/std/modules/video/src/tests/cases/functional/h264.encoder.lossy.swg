#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A picture with smooth areas, edges and fine detail, displaced by `shiftX` and `shiftY`.
func lossyScene(width, height, shiftX, shiftY: s32)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(cast(u64, width) * cast(u64, height) * 3)
    for y in height
    {
        for x in width
        {
            let sx = x + shiftX
            let sy = y + shiftY
            let at = (cast(u64, y) * cast(u64, width) + cast(u64, x)) * 3

            // A slow gradient, a grid of flat tiles, and a band of fine stripes.
            var value = (sx * 2 + sy) & 255
            if ((sx >> 4) + (sy >> 4)) & 1 do
                value = (value + 96) & 255
            if (sy >> 5) & 1 and sx & 2 do
                value = 255 - value
            rgb[at]     = cast(u8, value)
            rgb[at + 1] = cast(u8, (value * 3 + sx) & 255)
            rgb[at + 2] = cast(u8, (value + sy * 2) & 255)
        }
    }

    let image = Image.create(width, height, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

// Returns the mean squared luma error of a decoded picture against its source.
func lossyLumaError(source: const *Nv12Frame, decoded: const *PlanarFrame)->f64
{
    let luma = source.luma()
    var sum  = 0'u64
    for pixel in decoded.luma.count
    {
        let delta = cast(s64, luma[pixel]) - cast(s64, decoded.luma[pixel])
        sum += cast(u64, delta * delta)
    }

    return cast(f64, sum) / cast(f64, decoded.luma.count)
}

// The picture the encoder predicts from is the picture a decoder shows: after several moving
// pictures, intra and inter macroblocks, sub-sample motion, skipped blocks, deblocked edges and
// a size that is no multiple of sixteen, both hold the same samples.
#test
{
    const Width  = 100
    const Height = 70
    for qp in [12'u32, 26, 40]
    {
        let path = videoTempPath("h264-lossy-drift", "mp4")
        defer discard catch File.delete(path)
        var encoder   = expect H264.Encoder.create(Width, Height, quantizationQp: qp, sliceCount: 2)
        var writer    = expect Mp4.FragmentedWriter.create(path, Width, Height, 90_000, encoder.decoderConfig())
        var keyBytes  = 0'u64
        var lastBytes = 0'u64
        for index in 6's32
        {
            // Odd shifts land between chroma samples; the last picture repeats the one before.
            let shown  = Math.min(index, 4)
            let frame  = expect lossyScene(Width, Height, shown * 3, shown)
            let packet = expect encoder.encode(&frame, cast(u64, index) * 3_000, 3_000)
            if index == 0 do
                keyBytes = packet.bytes.count
            lastBytes = packet.bytes.count
            expect writer.addPacket(packet)
        }

        expect writer.end()
        Swag.require(lastBytes < keyBytes / 8, "a repeated picture costs next to nothing")

        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == 6)
        var decoded: PlanarFrame
        expect reader.decodeFramePlanesInto(&decoded, 5)
        Swag.require(decoded.width == Width and decoded.height == Height)

        let picture = encoder.lossy.reference()
        for row in Height
        {
            Swag.require(Memory.compare(picture.pixLuma(0, row), decoded.luma.storage() + cast(u64, row) * Width, Width) == 0,
                         "the encoder's luma differs from the decoder's")
        }

        for row in Height / 2
        {
            let at = cast(u64, row) * (Width / 2)
            Swag.require(Memory.compare(picture.pixChroma(0, 0, row), decoded.chromaB.storage() + at, Width / 2) == 0 and
                         Memory.compare(picture.pixChroma(1, 0, row), decoded.chromaR.storage() + at, Width / 2) == 0,
                         "the encoder's chroma differs from the decoder's")
        }
    }
}

// Motion is found and paid for as motion: a picture displaced by a fraction of a sample costs a
// small part of the picture it comes from, and stays close to its source.
#test
{
    const Width  = 192
    const Height = 128
    let path = videoTempPath("h264-lossy-motion", "mp4")
    defer discard catch File.delete(path)
    var encoder  = expect H264.Encoder.create(Width, Height, quantizationQp: 24, sliceCount: 2)
    var writer   = expect Mp4.FragmentedWriter.create(path, Width, Height, 90_000, encoder.decoderConfig())
    let first    = expect lossyScene(Width, Height, 0, 0)
    let moved    = expect lossyScene(Width, Height, 5, 3)
    let key      = expect encoder.encode(&first, 0, 3_000)
    let keyBytes = key.bytes.count
    expect writer.addPacket(key)
    let inter = expect encoder.encode(&moved, 3_000, 3_000)
    Swag.require(inter.bytes.count * 4 < keyBytes)
    expect writer.addPacket(inter)
    expect writer.end()

    // Most of the picture is predicted from a displaced block. The stripes repeat, so more than
    // one vector fits them and the vectors themselves are not compared.
    var followers = 0'u32
    for &mb in encoder.lossy.mbs where mb.inter and (mb.mvX != 0 or mb.mvY != 0) do
        followers += 1
    Swag.require(followers * 2 > cast(u32, encoder.lossy.mbs.count))

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 1)
    Swag.require(lossyLumaError(&moved, &decoded) < 40)
}

// A list scrolled by a few lines moves far, on detail no downhill search follows. The translation
// of the region is estimated from its rows and columns, and the picture costs little.
#test
{
    const Width  = 256
    const Height = 144

    func page(scroll: s32)->Nv12Frame fail
    {
        var rgb: Array'u8
        rgb.resize(Width * Height * 3)
        for y in Height
        {
            for x in Width
            {
                // Rows of short dark words on a light ground, different on every line.
                let line  = (y + scroll) / 12
                let hash  = cast #wrap (u32, (cast(u64, x / 3) + cast(u64, line) * 7_919) * 2_654_435_761)
                let inked = (y + scroll) % 12 < 8 and (hash >> 29) > 2
                let at    = (cast(u64, y) * Width + cast(u64, x)) * 3
                for channel in 3'u64 do
                    rgb[at + channel] = inked ? 32 : 236
            }
        }

        let image = Image.create(Width, Height, .RGB8, rgb.toSlice())
        var result: Nv12Frame
        try result.convertFrom(&image)
        return result
    }

    let path = videoTempPath("h264-lossy-scroll", "mp4")
    defer discard catch File.delete(path)
    var encoder  = expect H264.Encoder.create(Width, Height, quantizationQp: 26)
    var writer   = expect Mp4.FragmentedWriter.create(path, Width, Height, 90_000, encoder.decoderConfig())
    let first    = expect page(0)
    let scrolled = expect page(36)
    let key      = expect encoder.encode(&first, 0, 3_000)
    let keyBytes = key.bytes.count
    expect writer.addPacket(key)
    let inter = expect encoder.encode(&scrolled, 3_000, 3_000)

    // Only the three lines that came into view are new.
    Swag.require(inter.bytes.count * 2 < keyBytes)
    expect writer.addPacket(inter)
    expect writer.end()

    var scrolledBlocks = 0'u32

    // Pictures are stored bottom-up, so the sign of the vector is not what the fixture reads as.
    for &mb in encoder.lossy.mbs where mb.inter and mb.mvX == 0 and Math.abs(cast(s32, mb.mvY)) == 36 * 4 do
        scrolledBlocks += 1
    Swag.require(scrolledBlocks * 2 > cast(u32, encoder.lossy.mbs.count))
}

// The last column and row of a picture that is no multiple of sixteen are coded like the rest:
// no raw macroblock is left, in a key picture or after it.
#test
{
    const Width  = 130
    const Height = 74
    var encoder = expect H264.Encoder.create(Width, Height, quantizationQp: 26)
    let first   = expect lossyScene(Width, Height, 0, 0)
    let moved   = expect lossyScene(Width, Height, 2, 0)
    let key     = expect encoder.encode(&first, 0, 3_000)

    // Thirteen macroblocks hold an edge; raw, they alone took 384 bytes each.
    Swag.require(key.bytes.count < 13 * 384)
    let inter = expect encoder.encode(&moved, 3_000, 3_000)
    Swag.require(inter.bytes.count < 384)
}
