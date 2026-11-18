#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

func encoderStressPicture(shiftY: s32, flat: bool)->Nv12Frame fail
{
    const Width  = 1920
    const Height = 1080
    var rgb: Array'u8
    rgb.resize(Width * Height * 3)
    for y in Height
    {
        for x in Width
        {
            let sourceY = (y + shiftY) % Height
            let offset  = cast(u64, (y * Width + x) * 3)
            rgb[offset]     = flat ? 30 : cast(u8, (x * 7 + sourceY * 3) & 255)
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
            let value  = cast(u8, 30 + ((x / 4 * 17 + y / 4 * 31) % 160) + bright)
            let offset = cast(u64, (y * width + x) * 3)
            rgb[offset]     = value
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
            let value   = cast(u8,
                               special ? (changed ? 102 : 100) :
                               30 + ((x / 4 * 17 + y / 4 * 31) % 160))
            let offset = (y * cast(u64, width) + x) * 3
            rgb[offset]     = value
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
            .bytes[offset]     = cast(u8, cast(s32, .bytes[offset]) + deltaU)
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

    mtd stressIrregularLumaChroma()
    {
        let width  = cast(u64, .width)
        let chroma = width * cast(u64, .height)
        for mbY in cast(u64, .height) / 16
        {
            for mbX in width / 16
            {
                let luma = mbY * 16 * width + mbX * 16
                for row in 16'u64
                {
                    for column in 16'u64
                    {
                        let offset = luma + row * width + column
                        .bytes[offset] = cast(u8, (row * 17 + column * 31 + mbX * 7 + mbY * 13) & 255)
                    }
                }

                let uv = chroma + mbY * 8 * width + mbX * 16
                .bytes[uv] = cast(u8, cast(s32, .bytes[uv]) + 2)
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
    let base     = expect encoderStressPicture(0, false)
    let scrolled = expect encoderStressPicture(16, false)
    let flat     = expect encoderStressPicture(0, true)
    var encoder  = expect H264.Encoder.create(1920, 1080, keyInterval: 4)
    var writer   = expect Mp4.FragmentedWriter.create(path, 1920, 1080, 90_000, encoder.decoderConfig())

    let key = expect encoder.encode(&base, 0, 1_500)
    let keySize = key.bytes.count
    expect writer.addPacket(key)

    let scroll = expect encoder.encode(&scrolled, 1_500, 1_500)
    Swag.require(scroll.bytes.count < keySize / 4)
    expect writer.addPacket(scroll)

    let still = expect encoder.encode(&scrolled, 3_000, 1_500)
    Swag.require(still.bytes.count < keySize / 100)
    expect writer.addPacket(still)

    let changed = expect encoder.encode(&flat, 4_500, 1_500)
    Swag.require(changed.bytes.count < keySize / 16)
    expect writer.addPacket(changed)

    let flatKey = expect encoder.encode(&flat, 6_000, 1_500)
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
    let base      = expect encoderStressTiles(0)
    let brighter  = expect encoderStressTiles(1)
    let brightest = expect encoderStressTiles(2)
    var encoder   = expect H264.Encoder.create(1920, 1080)
    var writer    = expect Mp4.FragmentedWriter.create(path, 1920, 1080, 90_000, encoder.decoderConfig())
    let key = expect encoder.encode(&base, 0, 1_500)
    let keySize = key.bytes.count
    expect writer.addPacket(key)

    let faded = expect encoder.encode(&brighter, 1_500, 1_500)
    Swag.require(faded.bytes.count < keySize / 6)
    expect writer.addPacket(faded)

    let fadedAgain = expect encoder.encode(&brightest, 3_000, 1_500)
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
        let width  = resolution == 0 ? 1920 : 3840
        let height = resolution == 0 ? 1080 : 2160
        let path   = videoTempPath("h264-encoder-ac-sparse", "mp4")
        defer discard catch File.delete(path)
        let base    = expect encoderStressSparse(width, height, false)
        let changed = expect encoderStressSparse(width, height, true)
        var encoder = expect H264.Encoder.create(width, height)
        var writer  = expect Mp4.FragmentedWriter.create(path, width, height, 90_000, encoder.decoderConfig())
        let key = expect encoder.encode(&base, 0, 1_500)
        let keySize = key.bytes.count
        expect writer.addPacket(key)

        let sparse = expect encoder.encode(&changed, 1_500, 1_500)
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
    let base   = expect encoderStressTiles(0)
    var tinted = expect encoderStressTiles(0)
    tinted.stressTint(1, -1)
    var encoder = expect H264.Encoder.create(1920, 1080)
    var writer  = expect Mp4.FragmentedWriter.create(path, 1920, 1080, 90_000, encoder.decoderConfig())
    let key = expect encoder.encode(&base, 0, 1_500)
    let keySize = key.bytes.count
    expect writer.addPacket(key)

    let tint = expect encoder.encode(&tinted, 1_500, 1_500)
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
    let base    = expect encoderStressTiles(0)
    var changed = expect encoderStressTiles(0)
    changed.stressSparseChroma(2)
    var encoder = expect H264.Encoder.create(1920, 1080)
    var writer  = expect Mp4.FragmentedWriter.create(path, 1920, 1080, 90_000, encoder.decoderConfig())
    let key = expect encoder.encode(&base, 0, 1_500)
    let keySize = key.bytes.count
    expect writer.addPacket(key)

    let ac = expect encoder.encode(&changed, 1_500, 1_500)
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
    let base    = expect encoderStressTiles(0, 3840, 2160)
    var changed = expect encoderStressTiles(0, 3840, 2160)
    changed.stressSparseChroma(2)
    var encoder = expect H264.Encoder.create(3840, 2160)
    var writer  = expect Mp4.FragmentedWriter.create(path, 3840, 2160, 90_000, encoder.decoderConfig())
    let key = expect encoder.encode(&base, 0, 1_500)
    let keySize = key.bytes.count
    expect writer.addPacket(key)

    let ac = expect encoder.encode(&changed, 1_500, 1_500)
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

// Dense luma/chroma changes measure the fallback cost on a changing 4K picture.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("h264-encoder-irregular-4k", "mp4")
    defer discard catch File.delete(path)
    let base    = expect encoderStressTiles(0, 3840, 2160)
    var changed = expect encoderStressTiles(0, 3840, 2160)
    changed.stressIrregularLumaChroma()
    var encoder = expect H264.Encoder.create(3840, 2160)
    var writer  = expect Mp4.FragmentedWriter.create(path, 3840, 2160, 90_000, encoder.decoderConfig())
    let key     = expect encoder.encode(&base, 0, 1_500)
    expect writer.addPacket(key)
    let changedPacket = expect encoder.encode(&changed, 1_500, 1_500)
    Swag.require(changedPacket.bytes.count > key.bytes.count / 100)
    Swag.require(changedPacket.bytes.count < key.bytes.count * 2)
    expect writer.addPacket(changedPacket)
    expect writer.end()

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    requireStressPicture(&base, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 1)
    requireStressPicture(&changed, &decoded)
}

// A scene with moving screen texture and small colour changes exercises the
// quantized P path without depending on a platform capture device.
private impl Nv12Frame
{
    mtd qpStressTexture()
    {
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        for y in height
        {
            for x in width
            {
                let offset = y * width + x
                let delta  = cast(s32, (x * 13 + y * 7 + (x / 5) * 11) % 25) - 12
                let value  = cast(s32, .bytes[offset]) + delta
                .bytes[offset] = cast(u8, Math.max(16's32, Math.min(235's32, value)))
            }
        }

        let chroma = width * height
        for y in height / 2
        {
            for x in width / 2
            {
                let offset = chroma + y * width + x * 2
                let delta  = cast(s32, (x * 5 + y * 9) % 13) - 6
                .bytes[offset]     = cast(u8, cast(s32, .bytes[offset]) + delta)
                .bytes[offset + 1] = cast(u8, cast(s32, .bytes[offset + 1]) - delta)
            }
        }
    }

    mtd qpStressScroll(source: const *Nv12Frame)
    {
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        let luma   = source.luma()
        for y in height
        {
            let fromY = (y + 16) % height
            for x in width do
                .bytes[y * width + x] = luma[fromY * width + x]
        }
    }
}

private struct QpStressQuality
{
    yPsnr:  f64
    uvPsnr: f64
}

func qpStressQuality(reference: const *Nv12Frame, decoded: const *PlanarFrame)->QpStressQuality
{
    Swag.require(decoded.width == reference.width and decoded.height == reference.height)
    let y         = reference.luma()
    let uv        = reference.chroma()
    var ySquared  = 0'u64
    var uvSquared = 0'u64
    for index in y.count
    {
        let error = Math.abs(cast(s32, y[index]) - cast(s32, decoded.luma[index]))
        ySquared += cast(u64, error * error)
    }

    for index in decoded.chromaB.count
    {
        let errorU = Math.abs(cast(s32, uv[index * 2]) - cast(s32, decoded.chromaB[index]))
        let errorV = Math.abs(cast(s32, uv[index * 2 + 1]) - cast(s32, decoded.chromaR[index]))
        uvSquared += cast(u64, errorU * errorU + errorV * errorV)
    }

    let yMse  = cast(f64, ySquared) / cast(f64, y.count)
    let uvMse = cast(f64, uvSquared) / cast(f64, uv.count)
    return {yMse == 0 ? 99.0 : 10.0 * Math.log10(65_025.0 / yMse),
            uvMse == 0 ? 99.0 : 10.0 * Math.log10(65_025.0 / uvMse)}
}

func runQpStress(width, height: s32) fail
{
    let base = try encoderStressTiles(0, width, height)
    var targets = [base, try encoderStressTiles(0, width, height), try encoderStressTiles(0, width, height)]
    targets[1].qpStressScroll(&base)
    targets[2].qpStressTexture()
    var losslessTextureBytes: u64
    var qp28TextureBytes:     u64
    var qp28TextureY:         f64
    for qp in [0'u32, 28, 36]
    {
        for &target, scene in targets
        {
            let path = videoTempPath("h264-qp-stress", "mp4")
            defer discard catch File.delete(path)
            var encoder = try H264.Encoder.create(width, height, 60, qp)
            var writer  = try Mp4.FragmentedWriter.create(path, width, height, 90_000, encoder.decoderConfig())
            try writer.addPacket(try encoder.encode(&base, 0, 1_500))
            let packet = try encoder.encode(target, 1_500, 1_500)
            let packetBytes = packet.bytes.count
            try writer.addPacket(packet)
            try writer.end()

            var reader = try Reader.open(path)
            var decoded: PlanarFrame
            try reader.decodeFramePlanesInto(&decoded, 0)
            if qp == 0 do
                requireStressPicture(&base, &decoded)
            else
            {
                let quality = qpStressQuality(&base, &decoded)
                Swag.require(quality.yPsnr >= 18.0 and quality.uvPsnr >= 18.0)
            }

            try reader.decodeFramePlanesInto(&decoded, 1)
            if qp == 0
            {
                requireStressPicture(target, &decoded)
                if scene == 2 do
                    losslessTextureBytes = packetBytes
                continue
            }

            let quality = qpStressQuality(target, &decoded)
            Swag.require(quality.yPsnr >= 18.0 and quality.uvPsnr >= 18.0)
            if scene != 2 do
                continue

            Swag.require(packetBytes < losslessTextureBytes)
            if qp == 28
            {
                qp28TextureBytes = packetBytes
                qp28TextureY     = quality.yPsnr
                Swag.require(quality.yPsnr >= 30.0 and quality.uvPsnr >= 30.0)
            }
            else
            {
                Swag.require(packetBytes < qp28TextureBytes and quality.yPsnr < qp28TextureY)
                Swag.require(quality.yPsnr >= 27.0 and quality.uvPsnr >= 30.0)
            }
        }
    }
}

// Check lossless reconstruction and quantized size and quality at capture resolutions.
#[Swag.TestTag("stress")]
#test
{
    expect runQpStress(1920, 1080)
}

#[Swag.TestTag("stress")]
#test
{
    expect runQpStress(3840, 2160)
}

// Repeated raw input after a lossy P picture exposes unnecessary residual work
// when the encoder compares the input only with its reconstructed reference.
func runQpRepeatedInput(width, height: s32) fail
{
    let base   = try encoderStressTiles(0, width, height)
    var source = try encoderStressTiles(0, width, height)
    source.qpStressTexture()
    for qp in 2'u32
    {
        let selectedQp = qp == 0 ? 28'u32 : 36'u32
        let path       = videoTempPath("h264-qp-repeat", "mp4")
        defer discard catch File.delete(path)
        var encoder = try H264.Encoder.create(width, height, 60, selectedQp)
        var writer  = try Mp4.FragmentedWriter.create(path, width, height, 90_000, encoder.decoderConfig())
        try writer.addPacket(try encoder.encode(&base, 0, 1_500))
        try writer.addPacket(try encoder.encode(&source, 1_500, 1_500))
        for frame in 2'u64 until 4 do
            try writer.addPacket(try encoder.encode(&source, frame * 1_500, 1_500))
        try writer.end()

        var reader = try Reader.open(path)
        var decoded: PlanarFrame
        try reader.decodeFramePlanesInto(&decoded, 0)
        let idrQuality = qpStressQuality(&base, &decoded)
        Swag.require(idrQuality.yPsnr >= 18.0 and idrQuality.uvPsnr >= 18.0)
        for frame in 1'u64 until 4
        {
            try reader.decodeFramePlanesInto(&decoded, frame)
            let quality = qpStressQuality(&source, &decoded)
            Swag.require(quality.yPsnr >= 27.0 and quality.uvPsnr >= 30.0)
        }
    }
}

#[Swag.TestTag("stress")]
#test
{
    expect runQpRepeatedInput(1920, 1080)
}

#[Swag.TestTag("stress")]
#test
{
    expect runQpRepeatedInput(3840, 2160)
}

private impl Nv12Frame
{
    mtd qpStressUniformDelta()
    {
        let yCount = cast(u64, .width) * cast(u64, .height)
        for index in yCount do
            .bytes[index] += 5
        for index in yCount / 4
        {
            .bytes[yCount + index * 2]     += 3
            .bytes[yCount + index * 2 + 1] -= 3
        }
    }
}

// Decode one independent 4K picture to verify the output and check its size.
func qpStressIdrScene(source: const *Nv12Frame, qp: u32)->u64 fail
{
    let path = videoTempPath("h264-qp-idr-4k", "mp4")
    defer discard catch File.delete(path)
    var encoder = try H264.Encoder.create(source.width, source.height, 1, qp)
    var writer  = try Mp4.FragmentedWriter.create(path, source.width, source.height, 90_000, encoder.decoderConfig())
    let packet = try encoder.encode(source, 0, 1_500)
    let size   = packet.bytes.count
    try writer.addPacket(packet)
    try writer.end()

    var reader = try Reader.open(path)
    var decoded: PlanarFrame
    try reader.decodeFramePlanesInto(&decoded, 0)
    if qp == 0 do
        requireStressPicture(source, &decoded)
    else
    {
        let quality = qpStressQuality(source, &decoded)
        Swag.require(quality.yPsnr >= 25.0 and quality.uvPsnr >= 25.0)
    }

    return size
}

#[Swag.TestTag("stress")]
#test
{
    var flat   = expect encoderStressTiles(0, 3840, 2160)
    let yCount = 3840'u64 * 2160
    for index in yCount do
        flat.bytes[index] = 110
    for index in yCount / 2 do
        flat.bytes[yCount + index] = 128
    let textured          = expect encoderStressTiles(0, 3840, 2160)
    let flatExact         = expect qpStressIdrScene(&flat, 0)
    let texturedExact     = expect qpStressIdrScene(&textured, 0)
    let flatQuantized     = expect qpStressIdrScene(&flat, 36)
    let texturedQuantized = expect qpStressIdrScene(&textured, 36)
    Swag.require(flatQuantized < flatExact * 2)
    Swag.require(texturedQuantized < texturedExact / 4)
}

// A deterministic packet checksum permits an A/B check of entropy-only changes.
// Uniform screen deltas exercise single-DC CAVLC; texture exercises the general path.
func qpStressCavlcProbe(width, height: s32, qp, mode: u32) fail
{
    let base   = try encoderStressTiles(0, width, height)
    var source = try encoderStressTiles(0, width, height)
    if mode == 0
    {
        // Quantized IDR reconstruction can differ from the raw source. Build
        // the P picture from the decoder's reference so every 4x4 delta is
        // truly constant while the tiled picture remains non-flat.
        let anchorPath = videoTempPath("h264-qp-cavlc-anchor", "mp4")
        defer discard catch File.delete(anchorPath)
        var anchorEncoder = try H264.Encoder.create(width, height, 60, qp)
        var anchorWriter  = try Mp4.FragmentedWriter.create(anchorPath, width, height, 90_000, anchorEncoder.decoderConfig())
        try anchorWriter.addPacket(try anchorEncoder.encode(&base, 0, 1_500))
        try anchorWriter.end()
        var anchorReader = try Reader.open(anchorPath)
        var anchor: PlanarFrame
        try anchorReader.decodeFramePlanesInto(&anchor, 0)
        let yCount = cast(u64, width) * cast(u64, height)
        for index in yCount do
            source.bytes[index] = anchor.luma[index] + 5
        for index in yCount / 4
        {
            source.bytes[yCount + index * 2]     = anchor.chromaB[index] + 3
            source.bytes[yCount + index * 2 + 1] = anchor.chromaR[index] - 3
        }
    }
    else
    {
        source.qpStressTexture()
    }

    let path = videoTempPath("h264-qp-cavlc", "mp4")
    defer discard catch File.delete(path)
    var encoder = try H264.Encoder.create(width, height, 60, qp)
    var writer  = try Mp4.FragmentedWriter.create(path, width, height, 90_000, encoder.decoderConfig())
    try writer.addPacket(try encoder.encode(&base, 0, 1_500))
    let packet   = try encoder.encode(&source, 1_500, 1_500)
    let checksum = Hash.Crc32.compute(packet.bytes)
    try writer.addPacket(packet)
    try writer.end()

    var secondEncoder = try H264.Encoder.create(width, height, 60, qp)
    discard try secondEncoder.encode(&base, 0, 1_500)
    let secondPacket = try secondEncoder.encode(&source, 1_500, 1_500)
    Swag.require(Hash.Crc32.compute(secondPacket.bytes) == checksum)

    var reader = try Reader.open(path)
    var decoded: PlanarFrame
    try reader.decodeFramePlanesInto(&decoded, 1)
    let quality = qpStressQuality(&source, &decoded)
    if qp == 0 do
        requireStressPicture(&source, &decoded)
    else do
        Swag.require(quality.yPsnr >= 25.0 and quality.uvPsnr >= 25.0)
}

#[Swag.TestTag("stress")]
#test
{
    expect qpStressCavlcProbe(1920, 1080, 0, 0)
    expect qpStressCavlcProbe(1920, 1080, 28, 0)
    expect qpStressCavlcProbe(1920, 1080, 36, 0)
    expect qpStressCavlcProbe(3840, 2160, 28, 0)
    expect qpStressCavlcProbe(1920, 1080, 28, 1)
}
