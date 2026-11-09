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

    mtd stressIrregularLumaChroma()
    {
        let width = cast(u64, .width)
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

// Dense luma/chroma changes measure the fallback cost on a changing 4K picture.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("h264-encoder-irregular-4k", "mp4")
    defer discard catch File.delete(path)
    let base = expect encoderStressTiles(0, 3840, 2160)
    var changed = expect encoderStressTiles(0, 3840, 2160)
    changed.stressIrregularLumaChroma()
    var encoder = expect H264.Encoder.create(3840, 2160)
    var writer = expect Mp4.FragmentedWriter.create(path, 3840, 2160, 90_000,
                                                    encoder.decoderConfig())
    let key = expect encoder.encode(&base, 0, 1_500)
    expect writer.addPacket(key)
    var watch: Time.Stopwatch
    watch.start()
    let changedPacket = expect encoder.encode(&changed, 1_500, 1_500)
    watch.stop()
    Console.printf("H264 4K irregular change: % bytes, % us\n",
                   changedPacket.bytes.count, watch.elapsedMicroseconds())
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
        let width = cast(u64, .width)
        let height = cast(u64, .height)
        for y in height
        {
            for x in width
            {
                let offset = y * width + x
                let delta = cast(s32, (x * 13 + y * 7 + (x / 5) * 11) % 25) - 12
                let value = cast(s32, .bytes[offset]) + delta
                .bytes[offset] = cast(u8, Math.max(16's32, Math.min(235's32, value)))
            }
        }
        let chroma = width * height
        for y in height / 2
        {
            for x in width / 2
            {
                let offset = chroma + y * width + x * 2
                let delta = cast(s32, (x * 5 + y * 9) % 13) - 6
                .bytes[offset] = cast(u8, cast(s32, .bytes[offset]) + delta)
                .bytes[offset + 1] = cast(u8, cast(s32, .bytes[offset + 1]) - delta)
            }
        }
    }

    mtd qpStressScroll(source: const *Nv12Frame)
    {
        let width = cast(u64, .width)
        let height = cast(u64, .height)
        let luma = source.luma()
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
    maxY:   u32
    maxUv:  u32
}

func qpStressQuality(reference: const *Nv12Frame, decoded: const *PlanarFrame)->QpStressQuality
{
    Swag.require(decoded.width == reference.width and decoded.height == reference.height)
    let y = reference.luma()
    let uv = reference.chroma()
    var ySquared = 0'u64
    var uvSquared = 0'u64
    var maxY = 0'u32
    var maxUv = 0'u32
    for index in y.count
    {
        let error = Math.abs(cast(s32, y[index]) - cast(s32, decoded.luma[index]))
        ySquared += cast(u64, error * error)
        maxY = Math.max(maxY, cast(u32, error))
    }
    for index in decoded.chromaB.count
    {
        let errorU = Math.abs(cast(s32, uv[index * 2]) - cast(s32, decoded.chromaB[index]))
        let errorV = Math.abs(cast(s32, uv[index * 2 + 1]) - cast(s32, decoded.chromaR[index]))
        uvSquared += cast(u64, errorU * errorU + errorV * errorV)
        maxUv = Math.max(maxUv, cast(u32, Math.max(errorU, errorV)))
    }
    let yMse = cast(f64, ySquared) / cast(f64, y.count)
    let uvMse = cast(f64, uvSquared) / cast(f64, uv.count)
    return {yMse == 0 ? 99.0 : 10.0 * Math.log10(65_025.0 / yMse),
            uvMse == 0 ? 99.0 : 10.0 * Math.log10(65_025.0 / uvMse),
            maxY, maxUv}
}

func qpStressMedian(a, b, c: u64)->u64
    => a + b + c - Math.min(a, Math.min(b, c)) - Math.max(a, Math.max(b, c))

func runQpStress(width, height: s32) fail
{
    let base = try encoderStressTiles(0, width, height)
    var baselineBytes: [3] u64
    var qp28TextureBytes = 0'u64
    var qp28TextureY = 0.0'f64
    for qpIndex in 3'u32
    {
        let qp = qpIndex == 0 ? 0'u32 : (qpIndex == 1 ? 28'u32 : 36'u32)
        var idrTimes: [3] u64
        for scene in 3'u32
        {
            var target = try encoderStressTiles(0, width, height)
            if scene == 1 do
                target.qpStressScroll(&base)
            elif scene == 2 do
                target.qpStressTexture()
            let path = videoTempPath("h264-qp-stress", "mp4")
            defer discard catch File.delete(path)
            var encoder = try H264.Encoder.create(width, height, 60, qp)
            var writer = try Mp4.FragmentedWriter.create(path, width, height, 90_000,
                                                        encoder.decoderConfig())
            var watch: Time.Stopwatch
            watch.start()
            let idr = try encoder.encode(&base, 0, 1_500)
            watch.stop()
            let idrMicros = watch.elapsedMicroseconds()
            idrTimes[scene] = idrMicros
            let idrBytes = idr.bytes.count
            try writer.addPacket(idr)
            var micros: [3] u64
            var bytes: [3] u64
            var timestamp = 1_500'u64
            for repeat in 3'u64
            {
                watch.restart()
                let packet = try encoder.encode(&target, timestamp, 1_500)
                watch.stop()
                micros[repeat] = watch.elapsedMicroseconds()
                bytes[repeat] = packet.bytes.count
                try writer.addPacket(packet)
                timestamp += 1_500
                if repeat < 2
                {
                    try writer.addPacket(try encoder.encode(&base, timestamp, 1_500))
                    timestamp += 1_500
                }
            }
            try writer.end()
            let middleBytes = qpStressMedian(bytes[0], bytes[1], bytes[2])
            let middleMicros = qpStressMedian(micros[0], micros[1], micros[2])
            if qp == 0 do
                baselineBytes[scene] = middleBytes
            elif scene == 2 do
                Swag.require(middleBytes < baselineBytes[scene])
            var reader = try Reader.open(path)
            var decoded: PlanarFrame
            try reader.decodeFramePlanesInto(&decoded, 0)
            let idrQuality = qpStressQuality(&base, &decoded)
            if qp == 0 do
                requireStressPicture(&base, &decoded)
            else do
                Swag.require(idrQuality.yPsnr >= 18.0 and idrQuality.uvPsnr >= 18.0)
            var minY = 99.0'f64
            var minUv = 99.0'f64
            var maxY = 0'u32
            var maxUv = 0'u32
            for repeat in 3'u64
            {
                try reader.decodeFramePlanesInto(&decoded, repeat * 2 + 1)
                let quality = qpStressQuality(&target, &decoded)
                minY = Math.min(minY, quality.yPsnr)
                minUv = Math.min(minUv, quality.uvPsnr)
                maxY = Math.max(maxY, quality.maxY)
                maxUv = Math.max(maxUv, quality.maxUv)
                if qp == 0 do
                    requireStressPicture(&target, &decoded)
                else do
                    Swag.require(quality.yPsnr >= 18.0 and quality.uvPsnr >= 18.0)
            }
            if scene == 2 and qp == 28
            {
                qp28TextureBytes = middleBytes
                qp28TextureY = minY
                Swag.require(minY >= 32.0 and minUv >= 30.0)
            }
            elif scene == 2 and qp == 36
            {
                Swag.require(middleBytes < qp28TextureBytes and minY < qp28TextureY)
                Swag.require(minY >= 27.0 and minUv >= 30.0)
            }
            let sceneName = scene == 0 ? "still" : (scene == 1 ? "scroll" : "texture")
            let gopMbps = cast(f64, idrBytes + 59 * middleBytes) * 8.0 / 1_000_000.0
            Console.printf("H264 QP % % by % %: IDR % bytes, PSNR %/% dB; P median % bytes/% us; GOP60 % Mb/s; PSNR Y/UV %/% dB; max error %/%\n",
                           qp, width, height, sceneName, idrBytes,
                           idrQuality.yPsnr, idrQuality.uvPsnr,
                           middleBytes, middleMicros,
                           gopMbps, minY, minUv, maxY, maxUv)
        }
        Console.printf("H264 QP % % by % IDR median % us\n", qp, width, height,
                       qpStressMedian(idrTimes[0], idrTimes[1], idrTimes[2]))
    }
}

// Timing is diagnostic only; size, QP0 exactness, and decoded quality are asserted.
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
    let base = try encoderStressTiles(0, width, height)
    var source = try encoderStressTiles(0, width, height)
    source.qpStressTexture()
    for qp in 2'u32
    {
        let selectedQp = qp == 0 ? 28'u32 : 36'u32
        let path = videoTempPath("h264-qp-repeat", "mp4")
        defer discard catch File.delete(path)
        var encoder = try H264.Encoder.create(width, height, 60, selectedQp)
        var writer = try Mp4.FragmentedWriter.create(path, width, height, 90_000,
                                                     encoder.decoderConfig())
        try writer.addPacket(try encoder.encode(&base, 0, 1_500))
        let first = try encoder.encode(&source, 1_500, 1_500)
        let firstBytes = first.bytes.count
        try writer.addPacket(first)
        var repeatedBytes: [3] u64
        var repeatedMicros: [3] u64
        var watch: Time.Stopwatch
        for repeat in 3'u64
        {
            watch.restart()
            let packet = try encoder.encode(&source, (repeat + 2) * 1_500, 1_500)
            watch.stop()
            repeatedBytes[repeat] = packet.bytes.count
            repeatedMicros[repeat] = watch.elapsedMicroseconds()
            try writer.addPacket(packet)
        }
        try writer.end()
        Console.printf("H264 QP % % by % repeated raw texture: first % bytes; P2-P4 median % bytes/% us\n",
                       selectedQp, width, height, firstBytes,
                       qpStressMedian(repeatedBytes[0], repeatedBytes[1], repeatedBytes[2]),
                       qpStressMedian(repeatedMicros[0], repeatedMicros[1], repeatedMicros[2]))
        var reader = try Reader.open(path)
        var decoded: PlanarFrame
        try reader.decodeFramePlanesInto(&decoded, 0)
        let idrQuality = qpStressQuality(&base, &decoded)
        Swag.require(idrQuality.yPsnr >= 18.0 and idrQuality.uvPsnr >= 18.0)
        for frame in 1'u64 until 5
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
            .bytes[yCount + index * 2] += 3
            .bytes[yCount + index * 2 + 1] -= 3
        }
    }
}

// Measures helper cost separately from motion search, CAVLC and reference copying.
// The zero counts identify opportunities to skip inverse transforms safely.
func qpStressHelperProfile(width, height: s32, qp: u32, mode: u32) fail
{
    var reference = try encoderStressTiles(0, width, height)
    var source = try encoderStressTiles(0, width, height)
    if mode == 1 do
        source.qpStressUniformDelta()
    elif mode == 2
    {
        let yCount = cast(u64, width) * cast(u64, height)
        for index in yCount
        {
            reference.bytes[index] = 100
            source.bytes[index] = index & 1 ? 117 : 115
        }
        for index in yCount / 2
        {
            reference.bytes[yCount + index] = 128
            source.bytes[yCount + index] = (index / 2) & 1 ? 145 : 143
        }
    }
    else do
        source.qpStressTexture()
    let stride = cast(u64, width)
    let sourceY = source.luma()
    let referenceY = reference.luma()
    let sourceUv = source.chroma()
    let referenceUv = reference.chroma()
    var watch: Time.Stopwatch
    var zeroLuma = 0'u64
    var zeroChroma = 0'u64
    var dcOnlyLuma = 0'u64
    var dcOnlyChroma = 0'u64
    watch.start()
    for mbY in cast(u64, height) / 16
    {
        for mbX in stride / 16
        {
            for by in 4'u64
            {
                for bx in 4'u64
                {
                    let offset = (mbY * 16 + by * 4) * stride + mbX * 16 + bx * 4
                    var result: H264.InterLuma4x4Result
                    H264.quantizeInterLuma4x4(sourceY.buffer + offset,
                                              referenceY.buffer + offset,
                                              stride, stride, qp, &result)
                    if not result.nonZero do
                        zeroLuma += 1
                    elif result.nonZero == 1 and result.levels[0] do
                        dcOnlyLuma += 1
                }
            }
        }
    }
    watch.stop()
    let lumaMicros = watch.elapsedMicroseconds()
    watch.restart()
    for mbY in cast(u64, height) / 16
    {
        for mbX in stride / 16
        {
            let offset = mbY * 8 * stride + mbX * 16
            for plane in 2'u64
            {
                var result: H264.InterChroma8x8Result
                H264.quantizeInterChroma8x8(sourceUv.buffer + offset + plane,
                                            referenceUv.buffer + offset + plane,
                                            stride, stride, qp, 0, &result)
                if not result.cbp do
                    zeroChroma += 1
                elif result.cbp == 1 do
                    dcOnlyChroma += 1
            }
        }
    }
    watch.stop()
    let chromaMicros = watch.elapsedMicroseconds()
    let mbCount = cast(u64, width) * cast(u64, height) / 256
    Console.printf("H264 helper QP % % by % mode %: luma % us, zero %/%, DC-only %/% blocks; chroma % us, zero %/%, DC-only %/% planes\n",
                   qp, width, height, mode, lumaMicros, zeroLuma, mbCount * 16,
                   dcOnlyLuma, mbCount * 16, chromaMicros, zeroChroma, mbCount * 2,
                   dcOnlyChroma, mbCount * 2)
    Swag.require(zeroLuma <= mbCount * 16 and zeroChroma <= mbCount * 2)
}

#[Swag.TestTag("stress")]
#test
{
    expect qpStressHelperProfile(3840, 2160, 28, 0)
    expect qpStressHelperProfile(3840, 2160, 36, 0)
    expect qpStressHelperProfile(3840, 2160, 28, 1)
    expect qpStressHelperProfile(3840, 2160, 36, 1)
    expect qpStressHelperProfile(3840, 2160, 28, 2)
    expect qpStressHelperProfile(3840, 2160, 36, 2)
}

// Separate IDR cost from P-frame cost on a flat screen and a textured screen.
// Three independent IDRs give a median time, and Reader checks all three.
func qpStressIdrScene(source: const *Nv12Frame, qp, scene: u32)->u64 fail
{
    let path = videoTempPath("h264-qp-idr-4k", "mp4")
    defer discard catch File.delete(path)
    var encoder = try H264.Encoder.create(source.width, source.height, 1, qp)
    var writer = try Mp4.FragmentedWriter.create(path, source.width, source.height,
                                                 90_000, encoder.decoderConfig())
    var bytes: [3] u64
    var micros: [3] u64
    var watch: Time.Stopwatch
    for frame in 3'u64
    {
        watch.restart()
        let packet = try encoder.encode(source, frame * 1_500, 1_500)
        watch.stop()
        bytes[frame] = packet.bytes.count
        micros[frame] = watch.elapsedMicroseconds()
        try writer.addPacket(packet)
    }
    try writer.end()

    var reader = try Reader.open(path)
    var decoded: PlanarFrame
    var minY = 99.0'f64
    var minUv = 99.0'f64
    for frame in 3'u64
    {
        try reader.decodeFramePlanesInto(&decoded, frame)
        let quality = qpStressQuality(source, &decoded)
        minY = Math.min(minY, quality.yPsnr)
        minUv = Math.min(minUv, quality.uvPsnr)
        if qp == 0 do
            requireStressPicture(source, &decoded)
        else do
            Swag.require(quality.yPsnr >= 25.0 and quality.uvPsnr >= 25.0)
    }
    let middleBytes = qpStressMedian(bytes[0], bytes[1], bytes[2])
    Console.printf("H264 IDR 4K QP % scene %: % bytes, median % us, PSNR Y/UV %/% dB\n",
                   qp, scene, middleBytes, qpStressMedian(micros[0], micros[1], micros[2]),
                   minY, minUv)
    return middleBytes
}

#[Swag.TestTag("stress")]
#test
{
    var flat = expect encoderStressTiles(0, 3840, 2160)
    let yCount = 3840'u64 * 2160
    for index in yCount do
        flat.bytes[index] = 110
    for index in yCount / 2 do
        flat.bytes[yCount + index] = 128
    let textured = expect encoderStressTiles(0, 3840, 2160)
    let flatExact = expect qpStressIdrScene(&flat, 0, 0)
    let texturedExact = expect qpStressIdrScene(&textured, 0, 1)
    let flatQuantized = expect qpStressIdrScene(&flat, 36, 0)
    let texturedQuantized = expect qpStressIdrScene(&textured, 36, 1)
    Swag.require(flatQuantized < flatExact * 2)
    Swag.require(texturedQuantized < texturedExact / 4)
}
