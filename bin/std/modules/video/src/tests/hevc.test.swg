#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// Prediction-weight chroma offsets stay in their eight-bit syntax domain for Main 10. The
// reconstruction path applies the bit-depth scale exactly once after this derivation.
#test
{
    Swag.assert(Hevc.deriveChromaOffset(0, 3, 1) == -64)
    Swag.assert(Hevc.deriveChromaOffset(300, 3, 1) == 127)
    Swag.assert(Hevc.deriveChromaOffset(-300, 1, 1) == -128)
}

// The same access units, muxed two ways, decode to the same pictures.
//
// `ffmpeg-hevc-main.mkv` is a stream copy of `ffmpeg-hevc-main.mp4`, so a difference between these
// two results is the container reader and never the decoder.
#test
{
    videoAssertReferenceStream("ffmpeg-hevc-main", 96, 64, 60)
}

#test
{
    videoAssertReferenceStream("ffmpeg-hevc-main", 96, 64, 60, "mkv")
}

// An `hev1` sample entry, whose access units repeat the parameter sets the entry already carries,
// with three slices per picture so entropy contexts restart inside a frame.
#test
{
    videoAssertReferenceStream("ffmpeg-hevc-inband", 96, 64, 60)
}

// A forward seek crosses to the nearest sync sample instead of decoding the whole stream prefix,
// and the picture it lands on is the one that display rank names.
#test
{
    var source = expect ByteSource.openFile(videoFixturePath("ffmpeg-hevc-main.mp4").toString())
    var decoder:  Mp4.Decoder
    let idecoder: IDecoder = &decoder
    discard expect idecoder.open(&source)

    var expectedSync = cast(u64, decoder.video.hevc.sampleAtRank[47])
    while expectedSync > 0 and decoder.video.hevc.syncFlags[expectedSync] == 0 do
        expectedSync -= 1
    decoder.video.hevc.seekTo(47)
    Swag.assert(expectedSync > 0 and decoder.video.hevc.nextDecode == expectedSync)

    let reference = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-main.yuv").toString())
    var frame: Image
    expect idecoder.decodeFrame(&source, &frame)
    videoAssertReferenceFrame(frame, reference.toSlice(), 47, 96, 64)
    Swag.assert(decoder.video.hevc.skippedNonReference > 0)
}

// A player that falls behind may advance by several display ranks. That is a forward decode, not
// a random seek back through the group of pictures; references and already queued frames survive.
#test
{
    var source = expect ByteSource.openFile(videoFixturePath("ffmpeg-hevc-main.mp4").toString())
    var decoder:  Mp4.Decoder
    let idecoder: IDecoder = &decoder
    discard expect idecoder.open(&source)

    let reference = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-main.yuv").toString())
    var frame: Image
    var index     = 0'u64
    while index < 60
    {
        expect idecoder.seekFrame(&source, index)
        expect idecoder.decodeFrame(&source, &frame)
        videoAssertReferenceFrame(frame, reference.toSlice(), index, 96, 64)
        index += 3
    }

    Swag.assert(decoder.video.hevc.pending.count <= 4)
}

// The reader reports the track geometry from the decoder configuration record, before any access
// unit is read.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-hevc-main.mp4"))
    Swag.assert(reader.width() == 96 and reader.height() == 64)
    Swag.assert(reader.frameCount() == 60)
    Swag.assert(reader.hasPlanarFrames())
}

// Identity weights at integer positions go directly from the reference pictures to the result.
// This covers both the packed two-reference average and the packed ten-to-eight-bit handoff.
#test
{
    var sps: Hevc.Sps
    sps.width              = 32
    sps.height             = 32
    sps.subWidthC          = 2
    sps.subHeightC         = 2
    sps.chromaArrayType    = 1
    sps.bitDepthLuma       = 10
    sps.bitDepthChroma     = 10
    sps.matrixCoefficients = 1
    sps.fullRange          = true

    var current, reference0, reference1: Hevc.Frame
    current.prepare(&sps)
    reference0.prepare(&sps)
    reference1.prepare(&sps)
    for y in 32's32
    {
        for x in 32's32
        {
            reference0.lumaAtMutable(x, y)[0] = cast(u16, (x + y))
            reference1.lumaAtMutable(x, y)[0] = cast(u16, (100 + 2 * x + y))
        }
    }

    for y in 16's32
    {
        for x in 16's32
        {
            reference0.chromaAtMutable(0, x, y)[0] = cast(u16, (20 + x + y))
            reference1.chromaAtMutable(0, x, y)[0] = cast(u16, (60 + 2 * x + y))
            reference0.chromaAtMutable(1, x, y)[0] = cast(u16, (40 + x + y))
            reference1.chromaAtMutable(1, x, y)[0] = cast(u16, (80 + 2 * x + y))
        }
    }

    var pps: Hevc.Pps
    pps.weightedBipred = true
    var decoder: Hevc.Decoder
    decoder.activeSps            = &sps
    decoder.activePps            = &pps
    decoder.current              = &current
    decoder.header.sliceType     = Hevc.SliceTypeB
    decoder.header.hasWeights    = true
    decoder.refList.frames[0, 0] = &reference0
    decoder.refList.frames[1, 0] = &reference1
    for list in Hevc.ListCount
    {
        decoder.header.weights[list, 0].lumaWeight      = 1
        decoder.header.weights[list, 0].chromaWeight[0] = 1
        decoder.header.weights[list, 0].chromaWeight[1] = 1
    }

    var motion: Hevc.PuMotion
    motion.predFlags = 3
    motion.refIdx    = [0, 0]
    // Exercise the direct prediction paths at several block widths.
    for blockWidth in [4'u32, 8, 16, 32]
    {
        for blockY in 32 / blockWidth
        {
            for blockX in 32 / blockWidth do
                decoder.interPredict(cast(s32, (blockX * blockWidth)), cast(s32, (blockY * blockWidth)), blockWidth, blockWidth, &motion)
        }

        var picture: PlanarFrame
        current.writePlanar(&picture)
        Swag.assert(picture.matrix == .Bt709 and not picture.studioRange)
        for y in 32's32
        {
            for x in 32's32
            {
                let reconstructed = (x + y + 100 + 2 * x + y + 1) >> 1
                Swag.assert(picture.luma[cast(u64, y) * cast(u64, picture.strideLuma) + cast(u64, x)] == cast(u8, ((reconstructed + 2) >> 2)))
            }
        }

        for y in 16's32
        {
            for x in 16's32
            {
                let blue  = (20 + x + y + 60 + 2 * x + y + 1) >> 1
                let red   = (40 + x + y + 80 + 2 * x + y + 1) >> 1
                let index = cast(u64, y) * cast(u64, picture.strideChroma) + cast(u64, x)
                Swag.assert(picture.chromaB[index] == cast(u8, ((blue + 2) >> 2)))
                Swag.assert(picture.chromaR[index] == cast(u8, ((red + 2) >> 2)))
            }
        }
    }

    for bitDepth in [8'u32, 10]
    {
        sps.bitDepthLuma   = bitDepth
        sps.bitDepthChroma = bitDepth
        // Non-identity weights force integer-position samples through the interpolation buffer.
        decoder.header.weights[0, 0].lumaWeight      = 2
        decoder.header.weights[0, 0].chromaWeight[0] = 2
        decoder.header.weights[0, 0].chromaWeight[1] = 2
        motion.predFlags = 1
        motion.mv[0, 0] = 0
        motion.mv[0, 1] = 0
        for blockWidth in [4'u32, 8, 16, 32]
        {
            for blockY in 32 / blockWidth
            {
                for blockX in 32 / blockWidth do
                    decoder.interPredict(cast(s32, (blockX * blockWidth)), cast(s32, (blockY * blockWidth)), blockWidth, blockWidth, &motion)
            }

            for y in 32's32
            {
                for x in 32's32 do
                    Swag.assert(current.lumaAtMutable(x, y)[0] == cast(u16, (2 * (x + y))))
            }

            for y in 16's32
            {
                for x in 16's32
                {
                    Swag.assert(current.chromaAtMutable(0, x, y)[0] == cast(u16, (2 * (20 + x + y))))
                    Swag.assert(current.chromaAtMutable(1, x, y)[0] == cast(u16, (2 * (40 + x + y))))
                }
            }
        }

        // A motion vector beyond the padded reference exercises the gathered window as well.
        motion.mv[0, 0] = -800
        for blockWidth in [4'u32, 8, 16, 32]
        {
            for blockY in 32 / blockWidth
            {
                for blockX in 32 / blockWidth do
                    decoder.interPredict(cast(s32, (blockX * blockWidth)), cast(s32, (blockY * blockWidth)), blockWidth, blockWidth, &motion)
            }

            for y in 32's32
            {
                for x in 32's32 do
                    Swag.assert(current.lumaAtMutable(x, y)[0] == cast(u16, (2 * y)))
            }

            for y in 16's32
            {
                for x in 16's32
                {
                    Swag.assert(current.chromaAtMutable(0, x, y)[0] == cast(u16, (2 * (20 + y))))
                    Swag.assert(current.chromaAtMutable(1, x, y)[0] == cast(u16, (2 * (40 + y))))
                }
            }
        }

        // Exercise scalar remainders and fractional interpolation on gathered references.
        for motionX in [0's16, -800, -799]
        {
            motion.mv[0, 0] = motionX
            for blockWidth in [5'u32, 7, 12, 13]
            {
                decoder.interPredict(0, 0, blockWidth, blockWidth, &motion)
                for y in cast(s32, blockWidth)
                {
                    for x in cast(s32, blockWidth)
                    {
                        let sourceX = motionX == 0 ? x : 0
                        Swag.assert(current.lumaAtMutable(x, y)[0] == cast(u16, (2 * (sourceX + y))))
                    }
                }

                for y in cast(s32, (blockWidth / 2))
                {
                    for x in cast(s32, (blockWidth / 2))
                    {
                        let sourceX = motionX == 0 ? x : 0
                        Swag.assert(current.chromaAtMutable(0, x, y)[0] == cast(u16, (2 * (20 + sourceX + y))))
                        Swag.assert(current.chromaAtMutable(1, x, y)[0] == cast(u16, (2 * (40 + sourceX + y))))
                    }
                }
            }
        }

        // Both fractional filters read a gathered reference clamped to its top-left sample.
        motion.mv[0, 0] = -799
        motion.mv[0, 1] = -799
        for blockWidth in [4'u32, 5, 8, 12, 16, 32]
        {
            for index in 64'u32 * 64 do
                decoder.predSamples[index] = 0x5A5A
            for index in 32'u32 * 32 do
                decoder.residual[index] = 0x35353535
            decoder.interPredict(0, 0, blockWidth, blockWidth, &motion)
            for y in cast(s32, blockWidth)
            {
                for x in cast(s32, blockWidth) do
                    Swag.assert(current.lumaAtMutable(x, y)[0] == 0)
            }

            for y in cast(s32, (blockWidth / 2))
            {
                for x in cast(s32, (blockWidth / 2))
                {
                    Swag.assert(current.chromaAtMutable(0, x, y)[0] == 40)
                    Swag.assert(current.chromaAtMutable(1, x, y)[0] == 80)
                }
            }
        }
    }
}

// Bidirectional luma filtering uses decoder scratch when the window fits, and a separate
// buffer when it does not. Cover both sides of the capacity boundary with stale scratch.
#test
{
    var sps: Hevc.Sps
    sps.width           = 64
    sps.height          = 64
    sps.subWidthC       = 2
    sps.subHeightC      = 2
    sps.chromaArrayType = 1
    sps.bitDepthLuma    = 8
    sps.bitDepthChroma  = 8

    var current, reference: Hevc.Frame
    current.prepare(&sps)
    reference.prepare(&sps)
    for y in 64's32
    {
        for x in 64's32 do
            reference.lumaAtMutable(x, y)[0] = 49
    }
    for y in 32's32
    {
        for x in 32's32
        {
            reference.chromaAtMutable(0, x, y)[0] = 24
            reference.chromaAtMutable(1, x, y)[0] = 36
        }
    }

    var pps: Hevc.Pps
    pps.weightedBipred = true
    var decoder: Hevc.Decoder
    decoder.activeSps            = &sps
    decoder.activePps            = &pps
    decoder.current              = &current
    decoder.header.sliceType     = Hevc.SliceTypeB
    decoder.header.hasWeights    = true
    decoder.header.weights[0, 0].lumaWeight      = 2
    decoder.header.weights[0, 0].chromaWeight[0] = 2
    decoder.header.weights[0, 0].chromaWeight[1] = 2
    decoder.refList.frames[0, 0] = &reference

    var motion: Hevc.PuMotion
    motion.predFlags = 1
    motion.refIdx    = [0, 0]
    motion.mv[0, 0] = -799
    motion.mv[0, 1] = -799
    for bitDepth in [8'u32, 10]
    {
        sps.bitDepthLuma   = bitDepth
        sps.bitDepthChroma = bitDepth
        for height in [56'u32, 57, 64]
        {
            for index in 64'u32 * 64 do
                decoder.predSamples[index] = 0x5A5A
            decoder.interPredict(0, 0, 64, height, &motion)
            for y in cast(s32, height)
            {
                for x in 64's32 do
                    Swag.assert(current.lumaAtMutable(x, y)[0] == 98)
            }
            for y in cast(s32, (height / 2))
            {
                for x in 32's32
                {
                    Swag.assert(current.chromaAtMutable(0, x, y)[0] == 48)
                    Swag.assert(current.chromaAtMutable(1, x, y)[0] == 72)
                }
            }
        }
    }
}

// Vertical angular rows cover integral and fractional displacements in both
// directions, with exact four-column stores and a sentinel after the block.
#test
{
    var main: [160] u16
    var output: [32 * 32 + 1] u16
    var seed = 0x18BFA293'u32
    for bitDepth in [8'u32, 10]
    {
        let maximum = (1'u32 << bitDepth) - 1
        for size in [4'u32, 8, 16, 32]
        {
            for angle in [-32's32, -26, -17, -9, -2, 0, 2, 9, 17, 26, 32]
            {
                for i in main.count
                {
                    seed = seed * #wrap 1664525 + #wrap 1013904223
                    main[i] = cast(u16, (angle == 17 ? maximum : (seed >> 16) & maximum))
                }
                output[size * size] = 0x5A5A
                Hevc.predictAngularVertical(&main[64], &output[0], size, angle)
                for row in size
                {
                    let step = cast(s32, (row + 1)) * angle
                    let shift = step >> 5
                    let blend = step & 31
                    for x in size
                    {
                        let base = cast(u32, (64 + shift + 1 + cast(s32, x)))
                        let first = cast(u32, main[base])
                        let second = cast(u32, main[base + 1])
                        let expected = ((32 - cast(u32, blend)) * first + cast(u32, blend) * second + 16) >> 5
                        Swag.assert(output[row * size + x] == cast(u16, expected))
                    }
                }
                Swag.assert(output[size * size] == 0x5A5A)
                if size == 4
                {
                    Hevc.predictAngularHorizontal4(&main[64], &output[0], angle)
                    for column in size
                    {
                        let step = cast(s32, (column + 1)) * angle
                        let shift = step >> 5
                        let blend = step & 31
                        for y in size
                        {
                            let base = cast(u32, (64 + shift + 1 + cast(s32, y)))
                            let first = cast(u32, main[base])
                            let second = cast(u32, main[base + 1])
                            let expected = ((32 - cast(u32, blend)) * first + cast(u32, blend) * second + 16) >> 5
                            Swag.assert(output[y * size + column] == cast(u16, expected))
                        }
                    }
                    Swag.assert(output[size * size] == 0x5A5A)
                }
            }
        }
    }
}

// DC prediction fills the whole block, then blends only the luma edges of
// blocks smaller than 32 samples. Keep the next sample untouched.
#test
{
    var reference: Hevc.IntraReference
    var decoder: Hevc.Decoder
    var seed = 0x62EA417F'u32
    for bitDepth in [8'u32, 10]
    {
        let maximum = (1'u32 << bitDepth) - 1
        for log2Size in [2'u32, 3, 4, 5]
        {
            let size = 1'u32 << log2Size
            reference.size = size
            for iteration in 32'u32
            {
                var sum = size
                for index in size
                {
                    seed = seed * #wrap 1664525 + #wrap 1013904223
                    let top = iteration == 0 ? maximum : (seed >> 16) & maximum
                    seed = seed * #wrap 1664525 + #wrap 1013904223
                    let left = iteration == 0 ? maximum : (seed >> 16) & maximum
                    reference.setTop(index, cast(u16, top))
                    reference.setLeft(index, cast(u16, left))
                    sum += top + left
                }
                let dc = sum >> (log2Size + 1)
                for component in [0'u32, 1, 2]
                {
                    decoder.predSamples[size * size] = 0x5A5A
                    decoder.predictDc(&reference, size, log2Size, component)
                    for y in size
                    {
                        for x in size
                        {
                            var expected = dc
                            if component == 0 and size < 32
                            {
                                if x == 0 and y == 0 do
                                    expected = (cast(u32, reference.left(0)) + 2 * dc + cast(u32, reference.top(0)) + 2) >> 2
                                elif y == 0 do
                                    expected = (cast(u32, reference.top(x)) + 3 * dc + 2) >> 2
                                elif x == 0 do
                                    expected = (cast(u32, reference.left(y)) + 3 * dc + 2) >> 2
                            }
                            Swag.assert(decoder.predSamples[y * size + x] == cast(u16, expected))
                        }
                    }
                    Swag.assert(decoder.predSamples[size * size] == 0x5A5A)
                }
            }
        }
    }
}

// Planar prediction uses unsigned 16-bit sums up to the Main10 maximum.
// Compare all output samples and preserve the sentinel beyond the block.
#test
{
    var reference: Hevc.IntraReference
    var destination: [32 * 32 + 1] u16
    var seed = 0x63A21F89'u32
    for bitDepth in [8'u32, 10]
    {
        let maximum = (1'u32 << bitDepth) - 1
        for log2Size in [2'u32, 3, 4, 5]
        {
            let size = 1'u32 << log2Size
            reference.size = size
            for iteration in 32'u32
            {
                for index in size + 1
                {
                    seed = seed * #wrap 1664525 + #wrap 1013904223
                    let top = iteration == 0 ? maximum : (seed >> 16) & maximum
                    seed = seed * #wrap 1664525 + #wrap 1013904223
                    let left = iteration == 0 ? maximum : (seed >> 16) & maximum
                    reference.setTop(index, cast(u16, top))
                    reference.setLeft(index, cast(u16, left))
                }
                destination[size * size] = 0x5A5A
                if size == 4 do
                    Hevc.predictPlanar4(&reference, &destination[0])
                else do
                    Hevc.predictPlanarPacked(&reference, &destination[0], size, log2Size)
                let right = cast(u32, reference.top(size))
                let bottom = cast(u32, reference.left(size))
                for y in size
                {
                    let left = cast(u32, reference.left(y))
                    for x in size
                    {
                        let value = (size - 1 - x) * left + (x + 1) * right + (size - 1 - y) * cast(u32, reference.top(x)) + (y + 1) * bottom + size
                        Swag.assert(destination[y * size + x] == cast(u16, (value >> (log2Size + 1))))
                    }
                }
                Swag.assert(destination[size * size] == 0x5A5A)
            }
        }
    }
}

// Bypass and skipped transforms preserve signed coefficients, scaling and
// rounding for every block size without writing past the residual block.
#test
{
    var sps: Hevc.Sps
    var pps: Hevc.Pps
    var decoder: Hevc.Decoder
    decoder.activeSps = &sps
    decoder.activePps = &pps
    var seed = 0x825B9F31'u32
    for bitDepth in [8'u32, 10]
    {
        sps.bitDepthLuma = bitDepth
        sps.bitDepthChroma = bitDepth
        for log2Size in [2'u32, 3, 4, 5]
        {
            let size = 1'u32 << log2Size
            let count = size * size
            var block: Hevc.TransformBlock
            block.size = size
            block.log2Size = log2Size
            block.qp = 20
            decoder.coefficientColumns = cast(u32, ((1'u64 << size) - 1))
            for x in size do
                decoder.coefficientRows[x] = decoder.coefficientColumns
            for index in count
            {
                seed = seed * #wrap 1664525 + #wrap 1013904223
                decoder.coefficients[index] = cast #wrap(s16, (seed >> 16))
                decoder.residual[index] = 0x35353535
            }
            if count < 1024 do
                decoder.residual[count] = 0x35353535
            block.bypass = true
            decoder.reconstructResidual(&block)
            for index in count do
                Swag.assert(decoder.residual[index] == cast(s32, decoder.coefficients[index]))
            if count < 1024 do
                Swag.assert(decoder.residual[count] == 0x35353535)

            block.bypass = false
            block.transformSkip = true
            decoder.reconstructResidual(&block)
            let tsShift = 5 + cast(s32, log2Size)
            let bdShift = 20 - cast(s32, bitDepth)
            for index in count
            {
                let value = ((cast(s32, decoder.coefficients[index]) << tsShift) + (1 << (bdShift - 1))) >> bdShift
                Swag.assert(decoder.residual[index] == value)
            }
            if count < 1024 do
                Swag.assert(decoder.residual[count] == 0x35353535)
        }
    }
}

// Four-sample residual rows clip exactly in both reconstruction paths and leave the
// surrounding samples untouched, including at an unaligned block position.
#test
{
    var sps: Hevc.Sps
    sps.width = 16
    sps.height = 16
    sps.subWidthC = 2
    sps.subHeightC = 2
    sps.chromaArrayType = 1
    sps.bitDepthLuma = 8
    sps.bitDepthChroma = 8
    var frame: Hevc.Frame
    frame.prepare(&sps)
    var decoder: Hevc.Decoder
    decoder.activeSps = &sps
    decoder.current = &frame
    var seed = 0x2A72F8D5'u32
    for bitDepth in [8'u32, 10]
    {
        sps.bitDepthLuma = bitDepth
        sps.bitDepthChroma = bitDepth
        let maximum = cast(s32, ((1'u32 << bitDepth) - 1))
        for component in 3'u32
        {
            var block: Hevc.TransformBlock
            block.x = component == 0 ? 1 : 2
            block.y = component == 0 ? 1 : 2
            block.size = 4
            block.component = component
            let origin = component == 0 ? frame.lumaAtMutable(0, 0) : frame.chromaAtMutable(component - 1, 0, 0)
            let stride = component == 0 ? frame.strideLuma : frame.strideChroma
            for 64
            {
                var expected: [6, 6] u16
                for y in 6'u64
                {
                    for x in 6'u64
                    {
                        seed = seed * #wrap 1664525 + #wrap 1013904223
                        let value = cast(u16, ((seed >> 16) & cast(u32, maximum)))
                        origin[y * stride + x] = value
                        expected[y, x] = value
                    }
                }
                for y in 4'u64
                {
                    for x in 4'u64
                    {
                        seed = seed * #wrap 1664525 + #wrap 1013904223
                        let residual = cast(s32, ((seed >> 16) & 4095)) - 2048
                        decoder.residual[y * 4 + x] = residual
                        decoder.predSamples[y * 4 + x] = expected[y + 1, x + 1]
                        expected[y + 1, x + 1] = cast(u16, Math.clamp(cast(s32, expected[y + 1, x + 1]) + residual, 0, maximum))
                    }
                }
                decoder.addResidualInPlace(&block)
                for y in 6'u64
                {
                    for x in 6'u64 do
                        Swag.assert(origin[y * stride + x] == expected[y, x])
                }
                for y in 4'u64
                {
                    for x in 4'u64 do
                        origin[(y + 1) * stride + x + 1] = 0x5A5A
                }
                decoder.addResidual(&block, true)
                for y in 6'u64
                {
                    for x in 6'u64 do
                        Swag.assert(origin[y * stride + x] == expected[y, x])
                }
                decoder.addResidual(&block, false)
                for y in 4'u64
                {
                    for x in 4'u64 do
                        Swag.assert(origin[(y + 1) * stride + x + 1] == decoder.predSamples[y * 4 + x])
                }
            }
        }
    }
}

// Horizontal chroma deblocking processes two adjacent samples without reading or
// writing their neighbours. Compare the packed result to the normative scalar formula.
#test
{
    const Stride = 7'u64
    var samples:  [Stride * 4] u16
    var expected: [Stride * 4] u16
    var seed = 0x931BE27D'u32
    for bitDepth in [8'u32, 10]
    {
        let maximum = cast(s32, ((1'u32 << bitDepth) - 1))
        for tc in [1's32, 2, 4, 16, 96]
        {
            for 256
            {
                for index in samples.count
                {
                    seed = seed * #wrap 1664525 + #wrap 1013904223
                    samples[index]  = cast(u16, ((seed >> 16) & cast(u32, maximum)))
                    expected[index] = samples[index]
                }
                for lane in 2'u64
                {
                    let p1 = cast(s32, expected[1 + lane])
                    let p0 = cast(s32, expected[Stride + 1 + lane])
                    let q0 = cast(s32, expected[2 * Stride + 1 + lane])
                    let q1 = cast(s32, expected[3 * Stride + 1 + lane])
                    let delta = Math.clamp((((q0 - p0) << 2) + p1 - q1 + 4) >> 3, -tc, tc)
                    expected[Stride + 1 + lane]     = cast(u16, Math.clamp(p0 + delta, 0, maximum))
                    expected[2 * Stride + 1 + lane] = cast(u16, Math.clamp(q0 - delta, 0, maximum))
                }
                Hevc.filterChromaPair(&samples[2 * Stride + 1], cast(s64, Stride), tc, maximum)
                Swag.assert(samples == expected)
            }
        }
    }
}

// The vertical pair reads two rows and writes only p0 and q0 in each.
#test
{
    const Stride = 7'u64
    var samples:  [Stride * 2] u16
    var expected: [Stride * 2] u16
    var seed = 0x817F3C21'u32
    for bitDepth in [8'u32, 10]
    {
        let maximum = cast(s32, ((1'u32 << bitDepth) - 1))
        for tc in [1's32, 2, 4, 16, 96]
        {
            for 256
            {
                for index in samples.count
                {
                    seed = seed * #wrap 1664525 + #wrap 1013904223
                    samples[index]  = cast(u16, ((seed >> 16) & cast(u32, maximum)))
                    expected[index] = samples[index]
                }
                for row in 2'u64
                {
                    let base = row * Stride
                    let p1 = cast(s32, expected[base])
                    let p0 = cast(s32, expected[base + 1])
                    let q0 = cast(s32, expected[base + 2])
                    let q1 = cast(s32, expected[base + 3])
                    let delta = Math.clamp((((q0 - p0) << 2) + p1 - q1 + 4) >> 3, -tc, tc)
                    expected[base + 1] = cast(u16, Math.clamp(p0 + delta, 0, maximum))
                    expected[base + 2] = cast(u16, Math.clamp(q0 - delta, 0, maximum))
                }
                Hevc.filterChromaVerticalPair(&samples[2], cast(s64, Stride), tc, maximum)
                Swag.assert(samples == expected)
            }
        }
    }
}

// Compare all four transposed luma lines to the scalar filter, including the
// weak-filter rejection and both optional sides. Sentinel samples surround each row.
#test
{
    const Stride = 13'u64
    var decoder: Hevc.Decoder
    var samples: [Stride * 4] u16
    var expected: [Stride * 4] u16
    var seed = 0x15BDE271'u32
    for bitDepth in [8'u32, 10]
    {
        let maximum = cast(s32, ((1'u32 << bitDepth) - 1))
        for tc in [1's32, 2, 16, 96]
        {
            for strong in [false, true]
            {
                for filterP in [false, true]
                {
                    for filterQ in [false, true]
                    {
                        for 128
                        {
                            for index in samples.count
                            {
                                seed = seed * #wrap 1664525 + #wrap 1013904223
                                samples[index] = cast(u16, ((seed >> 16) & cast(u32, maximum)))
                                expected[index] = samples[index]
                            }
                            for row in 4'u64
                            {
                                let base = row * Stride + 5
                                let p3 = cast(s32, expected[base - 4])
                                let p2 = cast(s32, expected[base - 3])
                                let p1 = cast(s32, expected[base - 2])
                                let p0 = cast(s32, expected[base - 1])
                                let q0 = cast(s32, expected[base])
                                let q1 = cast(s32, expected[base + 1])
                                let q2 = cast(s32, expected[base + 2])
                                let q3 = cast(s32, expected[base + 3])
                                if strong
                                {
                                    let limit = 2 * tc
                                    expected[base - 1] = cast(u16, Math.clamp((p2 + 2 * p1 + 2 * p0 + 2 * q0 + q1 + 4) >> 3, p0 - limit, p0 + limit))
                                    expected[base - 2] = cast(u16, Math.clamp((p2 + p1 + p0 + q0 + 2) >> 2, p1 - limit, p1 + limit))
                                    expected[base - 3] = cast(u16, Math.clamp((2 * p3 + 3 * p2 + p1 + p0 + q0 + 4) >> 3, p2 - limit, p2 + limit))
                                    expected[base]     = cast(u16, Math.clamp((p1 + 2 * p0 + 2 * q0 + 2 * q1 + q2 + 4) >> 3, q0 - limit, q0 + limit))
                                    expected[base + 1] = cast(u16, Math.clamp((p0 + q0 + q1 + q2 + 2) >> 2, q1 - limit, q1 + limit))
                                    expected[base + 2] = cast(u16, Math.clamp((p0 + q0 + q1 + 3 * q2 + 2 * q3 + 4) >> 3, q2 - limit, q2 + limit))
                                }
                                else
                                {
                                    var delta = (9 * (q0 - p0) - 3 * (q1 - p1) + 8) >> 4
                                    if Math.abs(delta) < tc * 10
                                    {
                                        delta = Math.clamp(delta, -tc, tc)
                                        expected[base - 1] = cast(u16, Math.clamp(p0 + delta, 0, maximum))
                                        expected[base] = cast(u16, Math.clamp(q0 - delta, 0, maximum))
                                        if filterP
                                        {
                                            let half = tc >> 1
                                            let move = Math.clamp((((p2 + p0 + 1) >> 1) - p1 + delta) >> 1, -half, half)
                                            expected[base - 2] = cast(u16, Math.clamp(p1 + move, 0, maximum))
                                        }
                                        if filterQ
                                        {
                                            let half = tc >> 1
                                            let move = Math.clamp((((q2 + q0 + 1) >> 1) - q1 - delta) >> 1, -half, half)
                                            expected[base + 1] = cast(u16, Math.clamp(q1 + move, 0, maximum))
                                        }
                                    }
                                }
                            }
                            decoder.filterLumaVerticalQuad(&samples[5], cast(s64, Stride), strong, filterP, filterQ, tc, maximum)
                            Swag.assert(samples == expected)
                        }
                    }
                }
            }
        }
    }
}

// A stream can begin at a clean random access point whose leading pictures predict from what came
// before it. Those pictures are decoded from references that were never there, and clause 8.1.3
// says not to show them: they precede the point in output order, so keeping them would put wrong
// pictures before the first real one. The rank each would have had is answered by the first
// picture that is shown, and everything after it is what any other decoder produces.
#test
{
    var reader = expect Reader.open(videoFixturePath("edited-open-group-start.mkv"))
    Swag.assert(reader.width() == 96 and reader.height() == 64)

    let reference = expect File.readAllBytes(videoFixturePath("edited-open-group-start.yuv").toString())
    let bytes     = reference.toSlice()
    let frameSize = 96 * 64 * 3 / 2
    const Skipped = 4'u64

    var frame: PlanarFrame
    for rank in 12'u64
    {
        expect reader.decodeFramePlanesInto(&frame, Skipped + rank)
        for y in 64'u64
        {
            for x in 96'u64 do
                Swag.assert(frame.luma[y * cast(u64, frame.strideLuma) + x] == bytes[rank * frameSize + y * 96 + x])
        }
    }

    // Every rank the skipped pictures would have taken answers with the first one that is shown.
    var early: PlanarFrame
    expect reader.decodeFramePlanesInto(&early, 0)
    for y in 64'u64
    {
        for x in 96'u64 do
            Swag.assert(early.luma[y * cast(u64, early.strideLuma) + x] == bytes[y * 96 + x])
    }
}
