#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

func encoderStressPicture(shiftY: s32, flat: bool)->Nv12Frame fail
{
    const Width = 1920
    const Height = 1080
    var rgb: Array'u8
    rgb.resize(Width * Height * 3)
    for y in Height
    {
        for x in Width
        {
            let sourceY = (y + shiftY) % Height
            let offset = cast(u64, (y * Width + x) * 3)
            rgb[offset] = flat ? 30 : cast(u8, (x * 7 + sourceY * 3) & 255)
            rgb[offset + 1] = flat ? 90 : cast(u8, (x * 5 + sourceY * 11) & 255)
            rgb[offset + 2] = flat ? 200 : cast(u8, (x * 13 + sourceY * 2) & 255)
        }
    }
    let image = Image.create(Width, Height, .RGB8, rgb.toSlice())
    var frame: Nv12Frame
    try frame.convertFrom(&image)
    return frame
}

func encoderStressTiles(bright: s32, width: s32 = 1920, height: s32 = 1080)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(width * height * 3)
    for y in height
    {
        for x in width
        {
            let value = cast(u8, 30 + ((x / 4 * 17 + y / 4 * 31) % 160) + bright)
            let offset = cast(u64, (y * width + x) * 3)
            rgb[offset] = value
            rgb[offset + 1] = value
            rgb[offset + 2] = value
        }
    }
    let image = Image.create(width, height, .RGB8, rgb.toSlice())
    var frame: Nv12Frame
    try frame.convertFrom(&image)
    return frame
}

func encoderStressSparse(width, height: s32, changed: bool)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(cast(u64, width) * cast(u64, height) * 3)
    for y in cast(u64, height)
    {
        for x in cast(u64, width)
        {
            let special = x % 16 == 0 and y % 16 == 15
            let value = cast(u8, special ? (changed ? 102 : 100) :
                                 30 + ((x / 4 * 17 + y / 4 * 31) % 160))
            let offset = (y * cast(u64, width) + x) * 3
            rgb[offset] = value
            rgb[offset + 1] = value
            rgb[offset + 2] = value
        }
    }
    let image = Image.create(width, height, .RGB8, rgb.toSlice())
    var frame: Nv12Frame
    try frame.convertFrom(&image)
    return frame
}

func requireStressPicture(source: const *Nv12Frame, decoded: const *PlanarFrame)
{
    Swag.require(decoded.width == source.width and decoded.height == source.height)
    Swag.require(decoded.matrix == .Bt709 and decoded.studioRange)
    Swag.require(Slice.equals(decoded.luma.toSlice(), source.luma()))
    let uv = source.chroma()
    for index in decoded.chromaB.count
    {
        Swag.require(decoded.chromaB[index] == uv[index * 2])
        Swag.require(decoded.chromaR[index] == uv[index * 2 + 1])
    }
}

private impl Nv12Frame
{
    mtd stressTint(deltaU, deltaV: s32)
    {
        let start = cast(u64, .width) * cast(u64, .height)
        for index in (.bytes.count - start) / 2
        {
            let offset = start + index * 2
            .bytes[offset] = cast(u8, cast(s32, .bytes[offset]) + deltaU)
            .bytes[offset + 1] = cast(u8, cast(s32, .bytes[offset + 1]) + deltaV)
        }
    }

    mtd stressSparseChroma(delta: s32)
    {
        let width = cast(u64, .width)
        let start = width * cast(u64, .height)
        for mbY in cast(u64, .height) / 16
        {
            for mbX in width / 16
            {
                let offset = start + mbY * 8 * width + mbX * 16
                .bytes[offset] = cast(u8, cast(s32, .bytes[offset]) + delta)
            }
        }
    }
}

// Measures a textured IDR, 16px scroll, unchanged picture, and flat color at 1080p.
// Size gates are loose enough for bitstream improvements; elapsed time is only reported.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("h264-encoder-1080p", "mp4")
    defer discard catch File.delete(path)
    let base = expect encoderStressPicture(0, false)
    let scrolled = expect encoderStressPicture(16, false)
    let flat = expect encoderStressPicture(0, true)
    var encoder = expect H264.Encoder.create(1920, 1080, keyInterval: 4)
    var writer = expect Mp4.FragmentedWriter.create(path, 1920, 1080, 90_000,
                                                    encoder.decoderConfig())
    var watch: Time.Stopwatch

    watch.start()
    let key = expect encoder.encode(&base, 0, 1_500)
    watch.stop()
    let keySize = key.bytes.count
    Console.printf("H264 1080p textured IDR: % bytes, % us\n", keySize, watch.elapsedMicroseconds())
    expect writer.addPacket(key)

    watch.restart()
    let scroll = expect encoder.encode(&scrolled, 1_500, 1_500)
    watch.stop()
    Console.printf("H264 1080p 16px scroll: % bytes, % us\n", scroll.bytes.count,
                   watch.elapsedMicroseconds())
    Swag.require(scroll.bytes.count < keySize / 4)
    expect writer.addPacket(scroll)

    watch.restart()
    let still = expect encoder.encode(&scrolled, 3_000, 1_500)
    watch.stop()
    Console.printf("H264 1080p still: % bytes, % us\n", still.bytes.count,
                   watch.elapsedMicroseconds())
    Swag.require(still.bytes.count < keySize / 100)
    expect writer.addPacket(still)

    watch.restart()
    let changed = expect encoder.encode(&flat, 4_500, 1_500)
    watch.stop()
    Console.printf("H264 1080p flat change: % bytes, % us\n", changed.bytes.count,
                   watch.elapsedMicroseconds())
    Swag.require(changed.bytes.count < keySize / 16)
    expect writer.addPacket(changed)

    watch.restart()
    let flatKey = expect encoder.encode(&flat, 6_000, 1_500)
    watch.stop()
    Console.printf("H264 1080p flat IDR: % bytes, % us\n", flatKey.bytes.count,
                   watch.elapsedMicroseconds())
    Swag.require(flatKey.isKeyFrame and flatKey.bytes.count < keySize / 16)
    expect writer.addPacket(flatKey)
    expect writer.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 5)
    var decoded: PlanarFrame
    for index in 5'u64
    {
        expect reader.decodeFramePlanesInto(&decoded, index)
        let source = index == 0 ? &base : (index < 3 ? &scrolled : &flat)
        requireStressPicture(source, &decoded)
    }
}

// Measures exact DC-only residual compression on a varied 1080p grayscale picture.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("h264-encoder-1080p-dc", "mp4")
    defer discard catch File.delete(path)
    let base = expect encoderStressTiles(0)
    let brighter = expect encoderStressTiles(1)
    let brightest = expect encoderStressTiles(2)
    var encoder = expect H264.Encoder.create(1920, 1080)
    var writer = expect Mp4.FragmentedWriter.create(path, 1920, 1080, 90_000,
                                                    encoder.decoderConfig())
    var watch: Time.Stopwatch
    watch.start()
    let key = expect encoder.encode(&base, 0, 1_500)
    watch.stop()
    let keySize = key.bytes.count
    Console.printf("H264 1080p varied IDR: % bytes, % us\n", keySize,
                   watch.elapsedMicroseconds())
    expect writer.addPacket(key)

    watch.restart()
    let faded = expect encoder.encode(&brighter, 1_500, 1_500)
    watch.stop()
    Console.printf("H264 1080p DC residual: % bytes, % us\n", faded.bytes.count,
                   watch.elapsedMicroseconds())
    Swag.require(faded.bytes.count < keySize / 6)
    expect writer.addPacket(faded)

    watch.restart()
    let fadedAgain = expect encoder.encode(&brightest, 3_000, 1_500)
    watch.stop()
    Swag.require(fadedAgain.bytes.count < keySize / 6)
    expect writer.addPacket(fadedAgain)
    expect writer.end()

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    for index in 3'u64
    {
        expect reader.decodeFramePlanesInto(&decoded, index)
        let source = index == 0 ? &base : (index == 1 ? &brighter : &brightest)
        requireStressPicture(source, &decoded)
    }
}

// Sparse AC changes remain byte-exact through 1080p and 4K reference chains.
#[Swag.TestTag("stress")]
#test
{
    for resolution in 2'u64
    {
        let width = resolution == 0 ? 1920 : 3840
        let height = resolution == 0 ? 1080 : 2160
        let path = videoTempPath("h264-encoder-ac-sparse", "mp4")
        defer discard catch File.delete(path)
        let base = expect encoderStressSparse(width, height, false)
        let changed = expect encoderStressSparse(width, height, true)
        var encoder = expect H264.Encoder.create(width, height)
        var writer = expect Mp4.FragmentedWriter.create(path, width, height, 90_000,
                                                        encoder.decoderConfig())
        var watch: Time.Stopwatch
        watch.start()
        let key = expect encoder.encode(&base, 0, 1_500)
        watch.stop()
        let keySize = key.bytes.count
        Console.printf("H264 sparse % by % IDR: % bytes, % us\n", width, height, keySize,
                       watch.elapsedMicroseconds())
        expect writer.addPacket(key)

        watch.restart()
        let sparse = expect encoder.encode(&changed, 1_500, 1_500)
        watch.stop()
        Console.printf("H264 sparse % by % AC: % bytes, % us\n", width, height,
                       sparse.bytes.count, watch.elapsedMicroseconds())
        Swag.require(sparse.bytes.count < keySize / 16)
        expect writer.addPacket(sparse)
        let back = expect encoder.encode(&base, 3_000, 1_500)
        Swag.require(back.bytes.count < keySize / 16)
        expect writer.addPacket(back)
        expect writer.end()

        var reader = expect Reader.open(path)
        var decoded: PlanarFrame
        for index in 3'u64
        {
            expect reader.decodeFramePlanesInto(&decoded, index)
            requireStressPicture(index == 1 ? &changed : &base, &decoded)
        }
    }
}

// A screen-wide tint over textured luma exercises chroma DC on every macroblock.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("h264-encoder-chroma-1080p", "mp4")
    defer discard catch File.delete(path)
    let base = expect encoderStressTiles(0)
    var tinted = expect encoderStressTiles(0)
    tinted.stressTint(1, -1)
    var encoder = expect H264.Encoder.create(1920, 1080)
    var writer = expect Mp4.FragmentedWriter.create(path, 1920, 1080, 90_000,
                                                    encoder.decoderConfig())
    var watch: Time.Stopwatch
    watch.start()
    let key = expect encoder.encode(&base, 0, 1_500)
    watch.stop()
    let keySize = key.bytes.count
    expect writer.addPacket(key)

    watch.restart()
    let tint = expect encoder.encode(&tinted, 1_500, 1_500)
    watch.stop()
    Console.printf("H264 1080p chroma DC: % bytes, % us\n", tint.bytes.count,
                   watch.elapsedMicroseconds())
    Swag.require(tint.bytes.count < keySize / 20)
    expect writer.addPacket(tint)
    let back = expect encoder.encode(&base, 3_000, 1_500)
    Swag.require(back.bytes.count < keySize / 20)
    expect writer.addPacket(back)
    expect writer.end()

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    for index in 3'u64
    {
        expect reader.decodeFramePlanesInto(&decoded, index)
        requireStressPicture(index == 1 ? &tinted : &base, &decoded)
    }
}

// Sparse chroma AC over textured luma is smaller than PCM and remains exact at 1080p.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("h264-encoder-chroma-ac-1080p", "mp4")
    defer discard catch File.delete(path)
    let base = expect encoderStressTiles(0)
    var changed = expect encoderStressTiles(0)
    changed.stressSparseChroma(2)
    var encoder = expect H264.Encoder.create(1920, 1080)
    var writer = expect Mp4.FragmentedWriter.create(path, 1920, 1080, 90_000,
                                                    encoder.decoderConfig())
    var watch: Time.Stopwatch
    watch.start()
    let key = expect encoder.encode(&base, 0, 1_500)
    watch.stop()
    let keySize = key.bytes.count
    expect writer.addPacket(key)

    watch.restart()
    let ac = expect encoder.encode(&changed, 1_500, 1_500)
    watch.stop()
    Console.printf("H264 1080p chroma AC: % bytes, % us\n", ac.bytes.count,
                   watch.elapsedMicroseconds())
    Swag.require(ac.bytes.count < keySize / 10)
    expect writer.addPacket(ac)
    let back = expect encoder.encode(&base, 3_000, 1_500)
    Swag.require(back.bytes.count < keySize / 10)
    expect writer.addPacket(back)
    expect writer.end()

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    for index in 3'u64
    {
        expect reader.decodeFramePlanesInto(&decoded, index)
        requireStressPicture(index == 1 ? &changed : &base, &decoded)
    }
}

// The same chroma AC path is measured on a changing 4K picture.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("h264-encoder-chroma-ac-4k", "mp4")
    defer discard catch File.delete(path)
    let base = expect encoderStressTiles(0, 3840, 2160)
    var changed = expect encoderStressTiles(0, 3840, 2160)
    changed.stressSparseChroma(2)
    var encoder = expect H264.Encoder.create(3840, 2160)
    var writer = expect Mp4.FragmentedWriter.create(path, 3840, 2160, 90_000,
                                                    encoder.decoderConfig())
    var watch: Time.Stopwatch
    watch.start()
    let key = expect encoder.encode(&base, 0, 1_500)
    watch.stop()
    let keySize = key.bytes.count
    expect writer.addPacket(key)

    watch.restart()
    let ac = expect encoder.encode(&changed, 1_500, 1_500)
    watch.stop()
    Console.printf("H264 4K chroma AC: % bytes, % us\n", ac.bytes.count,
                   watch.elapsedMicroseconds())
    Swag.require(ac.bytes.count < keySize / 10)
    expect writer.addPacket(ac)
    expect writer.end()

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    requireStressPicture(&base, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 1)
    requireStressPicture(&changed, &decoded)
}
