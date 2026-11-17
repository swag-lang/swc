//! Format: H.264/AVC constrained-baseline encoder.
//! Supported: Progressive NV12, an exact mode at QP 0, and quantized pictures with Intra_16x16 and Intra_4x4 prediction, quarter-sample motion, P-skip, in-loop deblocking, and periodic IDR pictures.
//! Not supported: Rate control, B pictures, CABAC, and macroblock partitions.
//! Role: This file supplies encoded packets without an external codec or platform encoder.
//
#global namespace H264
#global export

using Core, Core.Errors

private struct EncoderMotion
{
    x:     s32
    y:     s32
    inter: bool
}

private struct EncoderSlicePacket
{
    bytes: Array'u8
}

// One scratch set per parallel slice keeps neighbour tables between pictures.
private struct EncoderSliceScratch
{
    motions:       Array'EncoderMotion
    pcm:           Array'bool
    nonZero:       Array'u8
    chromaNonZero: Array'u8
}

private const MotionOffsets: [16, 2] s32 = [
    [0, -2], [0, 2], [0, -4], [0, 4], [0, -8], [0, 8],
    [0, -16], [0, 16], [0, -32], [0, 32],
    [-16, 0], [16, 0], [-32, 0], [32, 0],
    [-16, -16], [16, 16]]

// Maps an inter coded-block pattern to its CAVLC code number.
//
// This is the inverse of Table 9-4's inter coded-block-pattern column. CAVLC writes the code for
// each residual macroblock, avoiding a scan of 48 entries per block.
const InterCbpToGolomb: [48] u8 = [
    0, 2, 3, 7, 4, 8, 17, 13, 5, 18, 9, 14, 10, 15, 16, 11,
    1, 32, 33, 36, 34, 37, 44, 40, 35, 45, 38, 41, 39, 42, 43, 19,
    6, 24, 25, 20, 26, 21, 46, 28, 27, 47, 22, 29, 23, 30, 31, 12]

// Raster coefficient position to H.264 4x4 zigzag scan position.
private const EncoderZigzagInverse: [16] u8 = [0, 1, 5, 6, 2, 4, 7, 12,
                                               3, 8, 11, 13, 9, 10, 14, 15]

// Encodes NV12 pictures as H.264 access units for a fragmented MP4 writer.
//
// QP 0 keeps every sample: flat intra blocks, exact residuals, integer-pixel copies and P-skip,
// with I_PCM for whatever these cannot hold. A positive QP trades precision for size: each
// macroblock is predicted from its neighbours or from the preceding picture at quarter-sample
// precision, only the quantized difference is written, and block edges are smoothed in the loop,
// so a decoder rebuilds the exact picture the encoder predicts from. The quantizer is fixed for
// the encoder's lifetime; the size of a picture follows its content. The result borrows the
// encoder's packet storage until the next call to encode. The AVC configuration remains valid
// for the encoder's lifetime and uses four-byte NAL lengths.
//
// ```swag
// #import("video")
// using Video
//
// let image = Pixel.Image.create(32, 16, .RGB8)
// var nv12: Nv12Frame
// try nv12.convertFrom(&image)
// var encoder = try H264.Encoder.create(32, 16)
// var writer = try Mp4.FragmentedWriter.create("capture.mp4", 32, 16, 90_000,
//                                             encoder.decoderConfig())
// try writer.addPacket(try encoder.encode(&nv12, 0, 3_000))
// try writer.end()
// ```
#[Swag.NoCopy]
struct Encoder
{
    private
    {
        config:         Array'u8
        packet:         Array'u8
        previous:       Array'u8
        previousInput:  Array'u8
        width:          s32
        height:         s32
        mbWidth:        u32
        mbHeight:       u32
        keyInterval:    u32
        quantizationQp: u32
        sliceCount:     u32
        frameNumber:    u32
        framesSinceKey: u32
        previousEnd:    u64
        hasFrame:       bool
        sliceScratch:   [8] EncoderSliceScratch
    }

    // Quantized pictures and the reference a decoder rebuilds from them.
    lossy: LossyCoder
}

impl Encoder
{
    // Creates an encoder for even NV12 dimensions and an IDR interval in frames.
    //
    // The image may be cropped within its final macroblock. Dimensions are limited to
    // 4096 pixels per side and 36864 macroblocks, matching H.264 level 5.2 frame size.
    // The interval is 1 to 255 pictures. A new encoder starts with an IDR picture.
    // `quantizationQp` is 0 for exact samples or 1 through 51 for quantized intra and
    // inter residuals.
    // `sliceCount` divides each picture into 1 to 8 complete macroblock-row bands.
    // The default single slice preserves the original bitstream.
    func create(width, height: s32, keyInterval: u32 = 60, quantizationQp: u32 = 0, sliceCount: u32 = 1)->Encoder fail
    {
        if width <= 0 or
           height <= 0 or
           width > 4096 or
           height > 4096 or
           width % 2 or
           height % 2 or
           not keyInterval or
           keyInterval > 255 or
           quantizationQp > 51 or
           not sliceCount or
           sliceCount > 8 do
            fail BadParameterError{"H.264 encoder needs even dimensions, an IDR interval of 1 to 255, QP of 0 to 51 and 1 to 8 slices"}
        let mbWidth  = cast(u32, (width + 15) / 16)
        let mbHeight = cast(u32, (height + 15) / 16)
        if mbWidth * mbHeight > 36_864 do
            fail UnsupportedFormatError{"H.264 encoder picture exceeds level 5.2 frame size"}
        if sliceCount > mbHeight do
            fail BadParameterError{"H.264 encoder needs at least one macroblock row per slice"}

        with var result: #returntype
        {
            .width          = width
            .height         = height
            .mbWidth        = mbWidth
            .mbHeight       = mbHeight
            .keyInterval    = keyInterval
            .quantizationQp = quantizationQp
            .sliceCount     = sliceCount
        }

        result.buildConfig()
        if quantizationQp do
            result.lossy.create(width, height, mbWidth, mbHeight, quantizationQp)
        return result
    }

    // Borrows the AVC decoder configuration until this encoder is destroyed.
    mtd const decoderConfig()->const [..] u8 => .config.toSlice()

    // Reports whether the next picture starts a new independently decodable GOP.
    internal mtd const willEncodeKeyFrame()->bool => not .hasFrame or .framesSinceKey >= .keyInterval

    // Encodes one picture and returns its MP4-ready access unit.
    //
    // The input must have the dimensions supplied to create and exactly one tightly packed
    // NV12 picture. Decode times may have gaps but cannot overlap; durations are positive.
    // The packet payload is borrowed until the next encode call. Validation failure leaves
    // the previously encoded picture and packet intact.
    mtd encode(frame: const *Nv12Frame, decodeTime: u64, duration: u32)->EncodedPacket fail
    {
        let expected = cast(u64, .width) * cast(u64, .height) * 3 / 2
        if frame.width != .width or frame.height != .height or frame.bytes.count != expected do
            fail BadParameterError{"H.264 encoder needs one NV12 picture of its configured size"}
        if not duration or
           decodeTime > Swag.U64.Max - duration or
           (.hasFrame and decodeTime < .previousEnd) do
            fail BadParameterError{"H.264 encoder packet timing is invalid"}

        if .hasFrame and .framesSinceKey < .keyInterval
        {
            let prior = .quantizationQp ? .previousInput.toSlice() : .previous.toSlice()
            if prior.count == frame.bytes.count and
               Memory.compare(prior.buffer, frame.bytes.storage(), prior.count) == 0 do
                return try .repeatPrevious(decodeTime, duration)
        }

        let key = not .hasFrame or .framesSinceKey >= .keyInterval
        var packet: Array'u8
        if .quantizationQp
        {
            .lossy.encodeFrame(frame, key, .frameNumber, .sliceCount, &packet)
        }
        elif .sliceCount == 1
        {
            .encodeSlice(frame, key, 0, &.sliceScratch[0], &packet)
        }
        else
        {
            var slices: Array'EncoderSlicePacket
            slices.resize(.sliceCount)
            let encoder = me
            let slots   = slices.storage()
            parallel for |encoder, frame, key, slots| sliceIndex in cast(u64, .sliceCount) do
                encoder.encodeSlice(frame, key, cast(u32, sliceIndex), &encoder.sliceScratch[sliceIndex], &slots[sliceIndex].bytes)
            for &slice in slices do
                packet.add(slice.bytes.toSlice())
        }

        .packet = #move packet
        if .quantizationQp
        {
            .previousInput.clear()
            .previousInput.add(frame.bytes.toSlice())
        }
        else
        {
            .previous.clear()
            .previous.add(frame.bytes.toSlice())
        }

        .previousEnd = decodeTime + duration
        .hasFrame    = true
        if key
        {
            .frameNumber    = 1
            .framesSinceKey = 1
        }
        else
        {
            .frameNumber    += 1
            .framesSinceKey += 1
        }

        let presentationTime = decodeTime
        return EncodedPacket{.packet.toSlice(), decodeTime, presentationTime, duration, key}
    }

    // Encodes one picture with the supplied base quantizer for the next picture only.
    // This is used by the software rate controller; fixed-QP callers use `encode`.
    internal mtd encodeAtQp(frame: const *Nv12Frame, decodeTime: u64, duration, qp: u32)->EncodedPacket fail
    {
        if not .quantizationQp or qp < 1 or qp > 51 do
            fail BadParameterError{"H.264 per-picture quantization needs an encoder in lossy mode and QP 1 to 51"}
        if frame.width != .width or frame.height != .height or
           frame.bytes.count != cast(u64, .width) * cast(u64, .height) * 3 / 2 do
            fail BadParameterError{"H.264 encoder needs one NV12 picture of its configured size"}
        if not duration or decodeTime > Swag.U64.Max - duration or
           (.hasFrame and decodeTime < .previousEnd) do
            fail BadParameterError{"H.264 encoder packet timing is invalid"}

        .quantizationQp = qp
        .lossy.baseQp = qp
        return try .encode(frame, decodeTime, duration)
    }

    // Holds the last encoded picture for another video slot without analyzing its pixels.
    //
    // The first picture must already have been encoded. At an IDR boundary the stored input
    // picture is encoded normally, preserving the configured clean-point interval. The packet
    // borrows its bytes until the next encode or repeat call.
    mtd repeatPrevious(decodeTime: u64, duration: u32)->EncodedPacket fail
    {
        if not .hasFrame do
            fail BadParameterError{"H.264 encoder has no previous picture to repeat"}
        if not duration or decodeTime > Swag.U64.Max - duration or decodeTime < .previousEnd do
            fail BadParameterError{"H.264 encoder packet timing is invalid"}

        if .framesSinceKey >= .keyInterval
        {
            var frame: Nv12Frame
            frame.copyPacked(.width, .height, .quantizationQp ? .previousInput.toSlice() : .previous.toSlice())
            return try .encode(&frame, decodeTime, duration)
        }

        var packet: Array'u8
        for sliceIndex in .sliceCount
        {
            let sliceStartY = sliceIndex * .mbHeight / .sliceCount
            let sliceEndY   = (sliceIndex + 1) * .mbHeight / .sliceCount
            var bits: EncoderBits
            bits.unsigned(sliceStartY * .mbWidth)
            bits.unsigned(0)     // P slice.
            bits.unsigned(0)     // pic_parameter_set_id.
            bits.bits(.frameNumber, 8)
            bits.bit(0)          // num_ref_idx_active_override_flag.
            bits.bit(0)          // ref_pic_list_modification_flag_l0.
            bits.bit(0)          // adaptive_ref_pic_marking_mode_flag.
            bits.unsigned(0)     // slice_qp_delta.
            bits.unsigned(1)     // Deblocking disabled.
            bits.unsigned((sliceEndY - sliceStartY) * .mbWidth)
            bits.trailing()
            appendEncoderNal(&packet, 0x41, bits.bytes.toSlice())
        }

        .packet         = #move packet
        .previousEnd    = decodeTime + duration
        .frameNumber    += 1
        .framesSinceKey += 1
        let presentationTime = decodeTime
        return EncodedPacket{.packet.toSlice(), decodeTime, presentationTime, duration, false}
    }
}

private impl Encoder
{
    // One independently coded row band. All spatial contexts restart at its first row.
    mtd encodeSlice(frame: const *Nv12Frame, key: bool, sliceIndex: u32, scratch: *EncoderSliceScratch, packet: *Array'u8)
    {
        let sliceStartY = sliceIndex * .mbHeight / .sliceCount
        let sliceEndY   = (sliceIndex + 1) * .mbHeight / .sliceCount
        var bits: EncoderBits
        bits.unsigned(sliceStartY * .mbWidth)     // first_mb_in_slice.
        bits.unsigned(key ? 2 : 0)     // I or P slice.
        bits.unsigned(0)     // pic_parameter_set_id.
        bits.bits(key ? 0 : .frameNumber, 8)
        if key do
            bits.unsigned(0)     // idr_pic_id.
        else
        {
            bits.bit(0)     // num_ref_idx_active_override_flag.
            bits.bit(0)     // ref_pic_list_modification_flag_l0.
        }

        if key
        {
            bits.bit(0)     // no_output_of_prior_pics_flag.
            bits.bit(0)     // long_term_reference_flag.
        }
        else do
            bits.bit(0)     // adaptive_ref_pic_marking_mode_flag.
        bits.unsigned(0)     // slice_qp_delta = 0.
        bits.unsigned(1)     // Disable deblocking; coded samples stay exact.

        var skipped       = 0'u32
        var currentQp     = 26's32
        let motions       = &scratch.motions
        let pcm           = &scratch.pcm
        let nonZero       = &scratch.nonZero
        let chromaNonZero = &scratch.chromaNonZero
        pcm.resize(cast(u64, .mbWidth) * .mbHeight)
        for &value in pcm[] do
            value[] = false
        if not key
        {
            motions.resize(cast(u64, .mbWidth) * cast(u64, .mbHeight))
            for &value in motions[] do
                value[] = {}
        }

        if not key
        {
            nonZero.resize(cast(u64, .mbWidth) * cast(u64, .mbHeight) * 16)
            for &value in nonZero[] do
                value[] = 0
            chromaNonZero.resize(cast(u64, .mbWidth) * cast(u64, .mbHeight) * 8)
            for &value in chromaNonZero[] do
                value[] = 0
        }

        for mbY in sliceStartY until sliceEndY
        {
            for mbX in .mbWidth
            {
                let motionIndex    = cast(u64, mbY) * .mbWidth + mbX
                let prediction     = key ? EncoderMotion{} : .predictMotion(motions.toSlice(), mbX, mbY, sliceStartY)
                var firstDifferent = 256'u32
                let same           = not key and .unchanged(frame, mbX, mbY, &firstDifferent)
                if same and .skipMotionIsZero(motions.toSlice(), mbX, mbY, sliceStartY)
                {
                    skipped += 1
                    motions[][motionIndex] = {0, 0, true}
                    continue
                }

                if not key do
                    bits.unsigned(skipped)
                if .flatIntra(frame, mbX, mbY, sliceStartY)
                {
                    bits.unsigned(key ? 3 : 8)     // Intra_16x16 DC, no coded AC/chroma.
                    bits.unsigned(0)     // Chroma DC prediction.
                    bits.signed(0)       // No QP change.
                    // P pictures can have inter residuals beside a flat intra block.
                    // Their coefficient counts select its DC token table.
                    if not key
                    {
                        var empty: [16] s16
                        discard bits.residual4(empty.buffer,
                                               .lumaNc(nonZero.toSlice(), mbX, mbY, 0, 0, sliceStartY))
                    }
                    else
                    {
                        .writeEmptyIntraDc(&bits, pcm.toSlice(), mbX, mbY, sliceStartY)
                    }

                    skipped = 0
                    continue
                }

                if not key
                {
                    var motion: EncoderMotion
                    if .findMotion(frame, mbX, mbY, prediction, same, &motion)
                    {
                        bits.unsigned(0)     // P_L0_16x16.
                        bits.signed(motion.x - prediction.x)
                        bits.signed(motion.y - prediction.y)
                        bits.unsigned(0)     // No residual coefficients.
                        motions[][motionIndex] = motion
                        skipped = 0
                        continue
                    }

                    if not .denseResidualLikelyOversized(frame, mbX, mbY, firstDifferent)
                    {
                        var chromaLevels:   [8] s16
                        var chromaAcLevels: [128] s16
                        var chromaChanged = false
                        var chromaCbp     = 0'u32
                        var chromaOkay    = .chromaDcResidual(frame, mbX, mbY, chromaLevels.buffer, &chromaChanged)
                        if chromaOkay and chromaChanged do
                            chromaCbp = 1
                        if not chromaOkay do
                            chromaOkay = .chromaAcResidual(frame, mbX, mbY, chromaLevels.buffer, chromaAcLevels.buffer, &chromaCbp)
                        if chromaOkay
                        {
                            var levels: [16] s32
                            var cbp = 0'u32
                            if (firstDifferent >= 256 and chromaCbp != 0) or
                               .dcResidual(frame, mbX, mbY, firstDifferent, levels.buffer, &cbp)
                            {
                                let oldBytes   = bits.bytes.count
                                let oldCurrent = bits.current
                                let oldUsed    = bits.used
                                let oldQp      = currentQp
                                bits.unsigned(0)     // P_L0_16x16 with zero motion.
                                bits.signed(-prediction.x)
                                bits.signed(-prediction.y)
                                let coded   = .writeDcResidual(&bits, nonZero.toSlice(), chromaNonZero.toSlice(), mbX, mbY, levels.buffer, cbp, chromaLevels.buffer, chromaAcLevels.buffer, chromaCbp, &currentQp, sliceStartY)
                                let written = bits.bytes.count * 8 + bits.used -
                                              (oldBytes * 8 + oldUsed)
                                if coded and written < 3_072
                                {
                                    motions[][motionIndex] = {0, 0, true}
                                    skipped = 0
                                    continue
                                }

                                bits.bytes.resize(oldBytes)
                                bits.current = oldCurrent
                                bits.used    = oldUsed
                                currentQp    = oldQp
                                for block in 16'u64 do
                                    nonZero[][motionIndex * 16 + block] = 0
                                for block in 8'u64 do
                                    chromaNonZero[][motionIndex * 8 + block] = 0
                            }

                            var acLevels: [256] s16
                            if .acResidual(frame, mbX, mbY, acLevels.buffer, &cbp)
                            {
                                let oldBytes   = bits.bytes.count
                                let oldCurrent = bits.current
                                let oldUsed    = bits.used
                                let oldQp      = currentQp
                                bits.unsigned(0)     // P_L0_16x16 with zero motion.
                                bits.signed(-prediction.x)
                                bits.signed(-prediction.y)
                                let coded   = .writeAcResidual(&bits, nonZero.toSlice(), chromaNonZero.toSlice(), mbX, mbY, acLevels.buffer, cbp, chromaLevels.buffer, chromaAcLevels.buffer, chromaCbp, &currentQp, 0, sliceStartY)
                                let written = bits.bytes.count * 8 + bits.used -
                                              (oldBytes * 8 + oldUsed)
                                if coded and written < 3_072
                                {
                                    motions[][motionIndex] = {0, 0, true}
                                    skipped = 0
                                    continue
                                }

                                bits.bytes.resize(oldBytes)
                                bits.current = oldCurrent
                                bits.used    = oldUsed
                                currentQp    = oldQp
                                for block in 16'u64 do
                                    nonZero[][motionIndex * 16 + block] = 0
                                for block in 8'u64 do
                                    chromaNonZero[][motionIndex * 8 + block] = 0
                            }
                        }
                    }
                }

                bits.unsigned(key ? 25 : 30)     // I_PCM in I/P slice type spaces.
                bits.alignZero()
                .writePcm(&bits, frame, mbX, mbY)
                pcm[][motionIndex] = true
                if not key
                {
                    for block in 16'u64 do
                        nonZero[][motionIndex * 16 + block] = 16
                    for block in 8'u64 do
                        chromaNonZero[][motionIndex * 8 + block] = 16
                }

                skipped = 0
            }
        }

        if not key and skipped do
            bits.unsigned(skipped)
        bits.trailing()
        appendEncoderNal(packet, key ? 0x65 : 0x41, bits.bytes.toSlice())
    }

    // Dense, strongly varying deltas tend to cost more CAVLC bits than one
    // exact I_PCM macroblock. Sample every luma 4x4 block only after motion
    // search fails; uniform, periodic and sparse changes still reach residual
    // coding. This heuristic can choose exact PCM without trying a smaller AC
    // representation, so it preserves samples but does not minimize every packet.
    mtd const denseResidualLikelyOversized(frame: const *Nv12Frame,
                                           mbX,
                                           mbY,
                                           firstDifferent: u32)->bool
    {
        if firstDifferent >= 256 do
            return false
        let x     = cast(u64, mbX) * 16
        let y     = cast(u64, mbY) * 16
        let width = cast(u64, .width)
        if x + 16 > width or y + 16 > cast(u64, .height) do
            return false
        let current       = frame.luma()
        var changed       = 0'u32
        var varyingBlocks = 0'u32
        var smallest      = 256's32
        var largest       = -256's32
        var smallestPair  = 512's32
        var largestPair   = -512's32
        for by in 4'u64
        {
            for bx in 4'u64
            {
                let offset    = (y + by * 4) * width + x + bx * 4
                let delta     = cast(s32, current[offset]) - cast(s32, .previous[offset])
                let nextDelta = cast(s32, current[offset + 1]) -
                                cast(s32, .previous[offset + 1])
                if delta != 0 do
                    changed += 1
                if Math.abs(nextDelta - delta) >= 16 do
                    varyingBlocks += 1
                smallest = Math.min(smallest, delta)
                largest  = Math.max(largest, delta)
                let pair = delta + nextDelta
                smallestPair = Math.min(smallestPair, pair)
                largestPair  = Math.max(largestPair, pair)
            }
        }

        return changed >= 12 and
               varyingBlocks >= 8 and
               largest - smallest >= 80 and
               largestPair - smallestPair >= 80
    }

    // Forward 4x4 integer transform and QP-0 quantization for a luma block.
    // The candidate is accepted only if the decoder's inverse transform reproduces
    // every source sample exactly, so reference pictures remain byte-exact.
    mtd const acBlock(frame: const *Nv12Frame, x, y: u64, levels: [*] s16)->bool
    {
        let width     = cast(u64, .width)
        let current   = frame.luma()
        var unchanged = true
        for row in 4'u64
        {
            let offset = (y + row) * width + x
            if Memory.compare(current.buffer + offset, .previous.storage() + offset, 4) != 0
            {
                unchanged = false
                break
            }
        }

        if unchanged
        {
            for scan in 16'u64 do
                levels[scan] = 0
            return true
        }

        var horizontal: [16] s32
        for row in 4'u64
        {
            let offset = (y + row) * width + x
            let a0     = cast(s32, current[offset]) - cast(s32, .previous[offset])
            let a1     = cast(s32, current[offset + 1]) - cast(s32, .previous[offset + 1])
            let a2     = cast(s32, current[offset + 2]) - cast(s32, .previous[offset + 2])
            let a3     = cast(s32, current[offset + 3]) - cast(s32, .previous[offset + 3])
            let s0     = a0 + a3
            let s1     = a1 + a2
            let s2     = a1 - a2
            let s3     = a0 - a3
            horizontal[row * 4]     = s0 + s1
            horizontal[row * 4 + 1] = 2 * s3 + s2
            horizontal[row * 4 + 2] = s0 - s1
            horizontal[row * 4 + 3] = s3 - 2 * s2
        }

        var scaled: [16] s16
        for column in 4'u64
        {
            let a0 = horizontal[column]
            let a1 = horizontal[4 + column]
            let a2 = horizontal[8 + column]
            let a3 = horizontal[12 + column]
            let s0 = a0 + a3
            let s1 = a1 + a2
            let s2 = a1 - a2
            let s3 = a0 - a3
            var coeffs: [4] s32 = [s0 + s1, 2 * s3 + s2,
                                   s0 - s1, s3 - 2 * s2]
            for row in 4'u64
            {
                let class       = (row & 1) + (column & 1)
                let factor      = class == 0 ? 13_107's32 : (class == 1 ? 8_066's32 : 5_243's32)
                let scale       = class == 0 ? 10's32 : (class == 1 ? 13's32 : 16's32)
                let coefficient = coeffs[row]
                let magnitude   = (Math.abs(coefficient) * factor + 16_384) >> 15
                if magnitude > 2_000 do
                    return false
                let quantized = coefficient < 0 ? -magnitude : magnitude
                scaled[column * 4 + row] = cast(s16, quantized * scale)

                // The decoder receives coefficients in zigzag order, then transposes
                // them into the transform's column-major storage.
                levels[EncoderZigzagInverse[row * 4 + column]] = cast(s16, quantized)
            }
        }

        var reconstructed: [16] u8
        for row in 4'u64
        {
            let offset = (y + row) * width + x
            for column in 4'u64 do
                reconstructed[row * 4 + column] = .previous[offset + column]
        }

        addIdct4x4Scalar(reconstructed.buffer, 4, scaled.buffer)
        for row in 4'u64
        {
            let offset = (y + row) * width + x
            for column in 4'u64 where
                reconstructed[row * 4 + column] != current[offset + column] do
                return false
        }

        return true
    }

    // Four flat 4x4 changes per plane are transformed as a 2x2 chroma DC block.
    // Only levels whose inverse dequantization reproduces all source bytes are accepted.
    mtd const chromaDcResidual(frame: const *Nv12Frame, mbX, mbY: u32, levels: [*] s16, changed: *bool)->bool
    {
        let x      = cast(u64, mbX) * 16
        let y      = cast(u64, mbY) * 16
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        if x + 16 > width or y + 16 > height do
            return false
        let current        = frame.chroma()
        let previousOffset = width * height
        changed[] = false
        for plane in 2'u64
        {
            var delta: [4] s32
            for by in 2'u64
            {
                for bx in 2'u64
                {
                    let first = (y / 2 + by * 4) * width + x + bx * 8 + plane
                    let block = by * 2 + bx
                    delta[block] = cast(s32, current[first]) -
                                   cast(s32, .previous[previousOffset + first])
                    if delta[block] != 0 do
                        changed[] = true
                    for row in 4'u64
                    {
                        let offset = first + row * width
                        for column in 4'u64 where
                            cast(s32, current[offset + column * 2]) -
                            cast(s32, .previous[previousOffset + offset + column * 2]) != delta[block] do
                            return false
                    }
                }
            }

            let d0 = delta[0]
            let d1 = delta[1]
            let d2 = delta[2]
            let d3 = delta[3]
            var transformed: [4] s32 = [d0 + d1 + d2 + d3, d0 - d1 + d2 - d3,
                                        d0 + d1 - d2 - d3, d0 - d1 - d2 + d3]
            for index in 4'u64
            {
                let level = transformed[index] * 16 / 5
                if Math.abs(level) > 1_000 do
                    return false
                levels[plane * 4 + index] = cast(s16, level)
            }

            let q0 = cast(s32, levels[plane * 4])
            let q1 = cast(s32, levels[plane * 4 + 1])
            let q2 = cast(s32, levels[plane * 4 + 2])
            let q3 = cast(s32, levels[plane * 4 + 3])
            if ((q0 + q1 + q2 + q3) * 5 + 32) >> 6 != d0 or
               ((q0 - q1 + q2 - q3) * 5 + 32) >> 6 != d1 or
               ((q0 + q1 - q2 - q3) * 5 + 32) >> 6 != d2 or
               ((q0 - q1 - q2 + q3) * 5 + 32) >> 6 != d3 do
                return false
        }

        return true
    }

    // Quantizes 4x4 chroma AC and the shared 2x2 DC transform at QP 0. The
    // candidate is used only if inverse reconstruction matches every input byte.
    mtd const chromaAcResidual(frame: const *Nv12Frame, mbX, mbY: u32, dc: [*] s16, ac: [*] s16, cbp: *u32)->bool
    {
        let x      = cast(u64, mbX) * 16
        let y      = cast(u64, mbY) * 8
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        if x + 16 > width or (cast(u64, mbY) + 1) * 16 > height do
            return false
        let current        = frame.chroma()
        let previousOffset = width * cast(u64, .height)
        var scaled:       [128] s16
        var blockChanged: [8] bool
        cbp[] = 0
        for plane in 2'u64
        {
            var rawDc: [4] s32
            for block in 4'u64
            {
                let bx      = block & 1
                let by      = block >> 1
                let blockX  = x + bx * 8 + plane
                let blockY  = y + by * 4
                let base    = (plane * 4 + block) * 16
                var changed = false
                for row in 4'u64
                {
                    let offset = (blockY + row) * width + blockX
                    for column in 4'u64 where
                        current[offset + column * 2] !=
                        .previous[previousOffset + offset + column * 2]
                    {
                        changed = true
                        break
                    }

                    if changed do
                        break
                }

                blockChanged[plane * 4 + block] = changed
                if not changed
                {
                    rawDc[block] = 0
                    for index in 16'u64
                    {
                        scaled[base + index] = 0
                        ac[base + index]     = 0
                    }

                    continue
                }

                var horizontal: [16] s32
                for row in 4'u64
                {
                    let offset = (blockY + row) * width + blockX
                    let a0     = cast(s32, current[offset]) - cast(s32, .previous[previousOffset + offset])
                    let a1     = cast(s32, current[offset + 2]) - cast(s32, .previous[previousOffset + offset + 2])
                    let a2     = cast(s32, current[offset + 4]) - cast(s32, .previous[previousOffset + offset + 4])
                    let a3     = cast(s32, current[offset + 6]) - cast(s32, .previous[previousOffset + offset + 6])
                    let s0     = a0 + a3
                    let s1     = a1 + a2
                    let s2     = a1 - a2
                    let s3     = a0 - a3
                    horizontal[row * 4]     = s0 + s1
                    horizontal[row * 4 + 1] = 2 * s3 + s2
                    horizontal[row * 4 + 2] = s0 - s1
                    horizontal[row * 4 + 3] = s3 - 2 * s2
                }

                for column in 4'u64
                {
                    let a0 = horizontal[column]
                    let a1 = horizontal[4 + column]
                    let a2 = horizontal[8 + column]
                    let a3 = horizontal[12 + column]
                    let s0 = a0 + a3
                    let s1 = a1 + a2
                    let s2 = a1 - a2
                    let s3 = a0 - a3
                    var coeffs: [4] s32 = [s0 + s1, 2 * s3 + s2,
                                           s0 - s1, s3 - 2 * s2]
                    for row in 4'u64
                    {
                        let raster = column * 4 + row
                        if not raster
                        {
                            rawDc[block] = coeffs[row]
                            ac[base]     = 0
                            continue
                        }

                        let class       = (row & 1) + (column & 1)
                        let factor      = class == 0 ? 13_107's32 : (class == 1 ? 8_066's32 : 5_243's32)
                        let scale       = class == 0 ? 10's32 : (class == 1 ? 13's32 : 16's32)
                        let coefficient = coeffs[row]
                        let magnitude   = (Math.abs(coefficient) * factor + 16_384) >> 15
                        if magnitude > 2_000 do
                            return false
                        let quantized = coefficient < 0 ? -magnitude : magnitude
                        scaled[base + raster] = cast(s16, quantized * scale)
                        ac[base + EncoderZigzagInverse[row * 4 + column]] = cast(s16, quantized)
                        if quantized != 0 do
                            cbp[] = 2
                    }
                }
            }

            let c0 = rawDc[0]
            let c1 = rawDc[1]
            let c2 = rawDc[2]
            let c3 = rawDc[3]
            var transformed: [4] s32 = [c0 + c1 + c2 + c3, c0 - c1 + c2 - c3,
                                        c0 + c1 - c2 - c3, c0 - c1 - c2 + c3]
            for index in 4'u64
            {
                let coefficient = transformed[index]
                let magnitude   = (Math.abs(coefficient) * 13_107 + 32_768) >> 16
                if magnitude > 1_000 do
                    return false
                let quantized = coefficient < 0 ? -magnitude : magnitude
                dc[plane * 4 + index] = cast(s16, quantized)
                if quantized != 0 and cbp[] == 0 do
                    cbp[] = 1
            }

            let q0 = cast(s32, dc[plane * 4])
            let q1 = cast(s32, dc[plane * 4 + 1])
            let q2 = cast(s32, dc[plane * 4 + 2])
            let q3 = cast(s32, dc[plane * 4 + 3])
            var inverse: [4] s32 = [q0 + q1 + q2 + q3, q0 - q1 + q2 - q3,
                                    q0 + q1 - q2 - q3, q0 - q1 - q2 + q3]
            for block in 4'u64
            {
                let bx     = block & 1
                let by     = block >> 1
                let blockX = x + bx * 8 + plane
                let blockY = y + by * 4
                let base   = (plane * 4 + block) * 16
                if not blockChanged[plane * 4 + block] and inverse[block] == 0 do
                    continue
                scaled[base] = cast(s16, inverse[block] * 5)
                var reconstructed: [16] u8
                for row in 4'u64
                {
                    let offset = (blockY + row) * width + blockX
                    for column in 4'u64 do
                        reconstructed[row * 4 + column] = .previous[previousOffset + offset + column * 2]
                }

                addIdct4x4Scalar(reconstructed.buffer, 4, scaled.buffer + base)
                for row in 4'u64
                {
                    let offset = (blockY + row) * width + blockX
                    for column in 4'u64 where
                        reconstructed[row * 4 + column] != current[offset + column * 2] do
                        return false
                }
            }
        }

        return cbp[] != 0
    }

    mtd const acResidual(frame: const *Nv12Frame, mbX, mbY: u32, levels: [*] s16, cbp: *u32)->bool
    {
        let x      = cast(u64, mbX) * 16
        let y      = cast(u64, mbY) * 16
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        if x + 16 > width or y + 16 > height do
            return false
        cbp[] = 0
        for by in 4'u64
        {
            for bx in 4'u64
            {
                let blockIndex = by * 4 + bx
                if not .acBlock(frame, x + bx * 4, y + by * 4, levels + blockIndex * 16) do
                    return false
                for scan in 16'u64 where levels[blockIndex * 16 + scan] != 0
                {
                    cbp[] |= 1'u32 << cast(u32, (by / 2) * 2 + bx / 2)
                    break
                }
            }
        }

        return cbp[] != 0
    }

    mtd const writeAcResidual(bits: *EncoderBits, nonZero, chromaNonZero: [..] u8, mbX, mbY: u32, levels: const [*] s16, cbp: u32, chromaLevels, chromaAcLevels: const [*] s16, chromaCbp: u32, currentQp: *s32, targetQp: s32, sliceStartY: u32, simpleLumaMask: u32 = 0)->bool
    {
        let pattern = cbp | (chromaCbp << 4)
        bits.unsigned(cast(u32, InterCbpToGolomb[pattern]))
        if pattern
        {
            bits.signed(targetQp - currentQp[])
            currentQp[] = targetQp
        }

        for quad in 4'u64 where cbp & (1'u32 << cast(u32, quad)) != 0
        {
            for cell in 4'u64
            {
                let bx          = cast(u32, (quad & 1) * 2 + (cell & 1))
                let by          = cast(u32, (quad >> 1) * 2 + (cell >> 1))
                let block       = by * 4 + bx
                let blockLevels = levels + block * 16
                let context     = .lumaNc(nonZero, mbX, mbY, bx, by, sliceStartY)
                let index       = (cast(u64, mbY) * .mbWidth + mbX) * 16 + block
                if simpleLumaMask & (1'u32 << block)
                {
                    bits.singleDc(blockLevels[0], context)
                    nonZero[index] = blockLevels[0] ? 1 : 0
                    continue
                }

                if not bits.residual4(blockLevels, context) do
                    return false
                var total = 0'u8
                for scan in 16'u64 where blockLevels[scan] != 0 do
                    total += 1
                nonZero[index] = total
            }
        }

        return .writeChromaResidual(bits, chromaNonZero, mbX, mbY, chromaLevels, chromaAcLevels, chromaCbp, sliceStartY)
    }

    // Detects an exact DC-only 4x4 luma residual at QP 0. Chroma is checked
    // separately. Inverse dequantization scales DC by ten, so a level is accepted
    // only when the decoder's rounded (level * 10) / 64 equals every input delta.
    mtd const dcResidual(frame: const *Nv12Frame, mbX, mbY: u32, firstDifferent: u32, levels: [*] s32, cbp: *u32)->bool
    {
        // The first changed luma sample is already known from the skip test. A DC-only
        // block needs one uniform delta, so reject an AC block before scanning
        // the other luma blocks. A chroma-only change uses the caller's DC path.
        if firstDifferent >= 256 do
            return false
        let x      = cast(u64, mbX) * 16
        let y      = cast(u64, mbY) * 16
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        if x + 16 > width or y + 16 > height do
            return false
        let luma        = frame.luma()
        let firstX      = x + cast(u64, firstDifferent % 16)
        let firstY      = y + cast(u64, firstDifferent / 16)
        let blockX      = firstX & ~3'u64
        let blockY      = firstY & ~3'u64
        let firstOffset = firstY * width + firstX
        let firstDelta  = cast(s32, luma[firstOffset]) - cast(s32, .previous[firstOffset])
        for row in 4'u64
        {
            let offset = (blockY + row) * width + blockX
            for column in 4'u64 where
                cast(s32, luma[offset + column]) - cast(s32, .previous[offset + column]) != firstDelta do
                return false
        }

        cbp[] = 0
        for by in 4'u64
        {
            for bx in 4'u64
            {
                let offset = (y + by * 4) * width + x + bx * 4
                let delta  = cast(s32, luma[offset]) - cast(s32, .previous[offset])
                let level  = delta * 64 / 10
                if (level * 10 + 32) >> 6 != delta do
                    return false
                for row in 4'u64
                {
                    for column in 4'u64
                    {
                        let pixel = offset + row * width + column
                        if cast(s32, luma[pixel]) - cast(s32, .previous[pixel]) != delta do
                            return false
                    }
                }

                levels[by * 4 + bx] = level
                if level != 0 do
                    cbp[] |= 1'u32 << cast(u32, (by / 2) * 2 + bx / 2)
            }
        }

        return cbp[] != 0
    }

    mtd const lumaNonZeroAt(nonZero: const [..] u8, mbX, mbY, bx, by: u32)->u32
    {
        let index = (cast(u64, mbY) * .mbWidth + mbX) * 16 + by * 4 + bx
        return nonZero[index]
    }

    mtd const lumaNc(nonZero: const [..] u8, mbX, mbY, bx, by, sliceStartY: u32)->u32
    {
        let hasLeft = bx > 0 or mbX > 0
        let hasTop  = by > 0 or mbY > sliceStartY
        let left    = bx > 0 ? .lumaNonZeroAt(nonZero, mbX, mbY, bx - 1, by) :
                      (mbX > 0 ? .lumaNonZeroAt(nonZero, mbX - 1, mbY, 3, by) : 0)
        let top = by > 0 ? .lumaNonZeroAt(nonZero, mbX, mbY, bx, by - 1) :
                  (mbY > sliceStartY ? .lumaNonZeroAt(nonZero, mbX, mbY - 1, bx, 3) : 0)
        if hasLeft and hasTop do
            return (left + top + 1) / 2
        return left + top
    }

    mtd const chromaNonZeroAt(nonZero: const [..] u8,
                              mbX,
                              mbY,
                              plane,
                              bx,
                              by: u32)->u32
    {
        let index = (cast(u64, mbY) * .mbWidth + mbX) * 8 + plane * 4 + by * 2 + bx
        return nonZero[index]
    }

    mtd const chromaNc(nonZero: const [..] u8,
                       mbX,
                       mbY,
                       plane,
                       bx,
                       by,
                       sliceStartY: u32)->u32
    {
        let hasLeft = bx > 0 or mbX > 0
        let hasTop  = by > 0 or mbY > sliceStartY
        let left    = bx > 0 ? .chromaNonZeroAt(nonZero, mbX, mbY, plane, bx - 1, by) :
                      (mbX > 0 ? .chromaNonZeroAt(nonZero, mbX - 1, mbY, plane, 1, by) : 0)
        let top = by > 0 ? .chromaNonZeroAt(nonZero, mbX, mbY, plane, bx, by - 1) :
                  (mbY > sliceStartY ? .chromaNonZeroAt(nonZero, mbX, mbY - 1, plane, bx, 1) : 0)
        if hasLeft and hasTop do
            return (left + top + 1) / 2
        return left + top
    }

    mtd const writeChromaResidual(bits: *EncoderBits, nonZero: [..] u8, mbX, mbY: u32, dc: const [*] s16, ac: const [*] s16, cbp: u32, sliceStartY: u32)->bool
    {
        if not cbp do
            return true
        for plane in 2'u64
        {
            if not bits.chromaDc(dc + plane * 4) do
                return false
        }

        if cbp < 2 do
            return true
        for plane in 2'u32
        {
            for block in 4'u32
            {
                let bx      = block & 1
                let by      = block >> 1
                let context = .chromaNc(nonZero, mbX, mbY, plane, bx, by, sliceStartY)
                let levels  = ac + (plane * 4 + block) * 16
                if not bits.residual15(levels + 1, context) do
                    return false
                var total = 0'u8
                for scan in 1'u64 until 16 where levels[scan] != 0 do
                    total += 1
                let index = (cast(u64, mbY) * .mbWidth + mbX) * 8 + plane * 4 + block
                nonZero[index] = total
            }
        }

        return true
    }

    mtd const writeDcResidual(bits: *EncoderBits, nonZero, chromaNonZero: [..] u8, mbX, mbY: u32, levels: const [*] s32, cbp: u32, chromaLevels, chromaAcLevels: const [*] s16, chromaCbp: u32, currentQp: *s32, sliceStartY: u32)->bool
    {
        let pattern = cbp | (chromaCbp << 4)
        bits.unsigned(cast(u32, InterCbpToGolomb[pattern]))
        bits.signed(-currentQp[])
        currentQp[] = 0

        for quad in 4'u64 where cbp & (1'u32 << cast(u32, quad)) != 0
        {
            for cell in 4'u64
            {
                let bx    = cast(u32, (quad & 1) * 2 + (cell & 1))
                let by    = cast(u32, (quad >> 1) * 2 + (cell >> 1))
                let level = levels[by * 4 + bx]
                bits.singleDc(level, .lumaNc(nonZero, mbX, mbY, bx, by, sliceStartY))
                let index = (cast(u64, mbY) * .mbWidth + mbX) * 16 + by * 4 + bx
                nonZero[index] = level == 0 ? 0 : 1
            }
        }

        return .writeChromaResidual(bits, chromaNonZero, mbX, mbY, chromaLevels, chromaAcLevels, chromaCbp, sliceStartY)
    }

    // A constant 16x16 block is represented by Intra_16x16 DC without coefficients when
    // every available top and left boundary has the same samples in all three planes.
    mtd const flatIntra(frame: const *Nv12Frame, mbX, mbY, sliceStartY: u32)->bool
    {
        let x      = cast(u64, mbX) * 16
        let y      = cast(u64, mbY) * 16
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        if not mbX and mbY == sliceStartY do
            return false
        let luma   = frame.luma()
        let chroma = frame.chroma()
        let valueY = luma[y * width + x]
        let valueU = chroma[y / 2 * width + x]
        let valueV = chroma[y / 2 * width + x + 1]

        // A complete macroblock can compare a whole row at once. Cropped edges
        // keep the padded scalar path below.
        if x + 16 <= width and y + 16 <= height
        {
            var expectedY, expectedUv: [16] u8
            for index in 16'u64 do
                expectedY[index] = valueY
            for index in 8'u64
            {
                expectedUv[index * 2]     = valueU
                expectedUv[index * 2 + 1] = valueV
            }

            for row in 16'u64 where
                Memory.compare(luma.buffer + (y + row) * width + x,
                               expectedY.buffer,
                               16) != 0 do
                return false
            for row in 8'u64 where
                Memory.compare(chroma.buffer + (y / 2 + row) * width + x,
                               expectedUv.buffer,
                               16) != 0 do
                return false
            if mbY > sliceStartY
            {
                if Memory.compare(luma.buffer + (y - 1) * width + x,
                                  expectedY.buffer,
                                  16) != 0 or
                   Memory.compare(chroma.buffer + (y / 2 - 1) * width + x,
                                  expectedUv.buffer,
                                  16) != 0 do
                    return false
            }

            if mbX
            {
                for row in 16'u64 where luma[(y + row) * width + x - 1] != valueY do
                    return false
                for row in 8'u64
                {
                    let at = (y / 2 + row) * width + x - 2
                    if chroma[at] != valueU or chroma[at + 1] != valueV do
                        return false
                }
            }

            return true
        }

        for row in 16'u64
        {
            let sourceY = Math.min(y + row, height - 1)
            for column in 16'u64 where luma[sourceY * width + Math.min(x + column, width - 1)] != valueY do
                return false
        }

        for row in 8'u64
        {
            for column in 8'u64
            {
                let sourceY = Math.min(y / 2 + row, height / 2 - 1)
                let sourceX = Math.min(x + column * 2, width - 2)
                let offset  = sourceY * width + sourceX
                if chroma[offset] != valueU or chroma[offset + 1] != valueV do
                    return false
            }
        }

        if mbY > sliceStartY
        {
            for column in 16'u64 where luma[(y - 1) * width + Math.min(x + column, width - 1)] != valueY do
                return false
            for column in 8'u64
            {
                let offset = (y / 2 - 1) * width + Math.min(x + column * 2, width - 2)
                if chroma[offset] != valueU or chroma[offset + 1] != valueV do
                    return false
            }
        }

        if mbX
        {
            for row in 16'u64 where luma[Math.min(y + row, height - 1) * width + x - 1] != valueY do
                return false
            for row in 8'u64
            {
                let offset = Math.min(y / 2 + row, height / 2 - 1) * width + x - 2
                if chroma[offset] != valueU or chroma[offset + 1] != valueV do
                    return false
            }
        }

        return true
    }

    mtd const writeEmptyIntraDc(bits: *EncoderBits, pcm: const [..] bool, mbX, mbY, sliceStartY: u32)
    {
        let left = mbX > 0 ? (pcm[cast(u64, mbY) * .mbWidth + mbX - 1] ? 16'u32 : 0) : 0
        let top  = mbY > sliceStartY ? (pcm[cast(u64, mbY - 1) * .mbWidth + mbX] ? 16'u32 : 0) : 0
        let nC   = mbX > 0 and mbY > sliceStartY ? (left + top + 1) / 2 : left + top
        if nC < 2 do
            bits.bit(1)
        elif nC < 4 do
            bits.bits(3, 2)
        elif nC < 8 do
            bits.bits(15, 4)
        else do
            bits.bits(3, 6)
    }

    mtd const motionAt(motions: const [..] EncoderMotion, x, y: s32)->EncoderMotion
    {
        if x < 0 or y < 0 or x >= cast(s32, .mbWidth) or y >= cast(s32, .mbHeight) do
            return {}
        return motions[cast(u64, y) * .mbWidth + cast(u64, x)]
    }

    // Section 8.4.1.3: 16x16 L0 vector prediction from A, B, and C (or D).
    mtd const predictMotion(motions: const [..] EncoderMotion,
                            mbX,
                            mbY,
                            sliceStartY: u32)->EncoderMotion
    {
        let x = cast(s32, mbX)
        let y = cast(s32, mbY)
        let a = .motionAt(motions, x - 1, y)
        let b = mbY > sliceStartY ? .motionAt(motions, x, y - 1) : EncoderMotion{}
        var c = mbY > sliceStartY ? .motionAt(motions, x + 1, y - 1) : EncoderMotion{}
        if mbY > sliceStartY and x + 1 >= cast(s32, .mbWidth) do
            c = .motionAt(motions, x - 1, y - 1)

        let availableA = x > 0
        let availableB = mbY > sliceStartY
        let availableC = mbY > sliceStartY and (x + 1 < cast(s32, .mbWidth) or x > 0)
        if availableA and not availableB and not availableC do
            return a
        if a.inter and not b.inter and not c.inter do
            return a
        if b.inter and not a.inter and not c.inter do
            return b
        if c.inter and not a.inter and not b.inter do
            return c

        let middleX = Math.max(Math.min(a.x, b.x), Math.min(Math.max(a.x, b.x), c.x))
        let middleY = Math.max(Math.min(a.y, b.y), Math.min(Math.max(a.y, b.y), c.y))
        return {middleX, middleY, true}
    }

    mtd const skipMotionIsZero(motions: const [..] EncoderMotion,
                               mbX,
                               mbY,
                               sliceStartY: u32)->bool
    {
        if mbX == 0 or mbY == sliceStartY do
            return true
        let a = .motionAt(motions, cast(s32, mbX) - 1, cast(s32, mbY))
        let b = .motionAt(motions, cast(s32, mbX), cast(s32, mbY) - 1)
        if a.inter and a.x == 0 and a.y == 0 do
            return true
        if b.inter and b.x == 0 and b.y == 0 do
            return true
        let predicted = .predictMotion(motions, mbX, mbY, sliceStartY)
        return predicted.x == 0 and predicted.y == 0
    }

    // Tests exact whole-pixel matches against the previous picture, including interleaved
    // chroma. A motion copy never reaches into a cropped or padded edge macroblock.
    mtd const matchesMotion(frame: const *Nv12Frame, mbX, mbY: u32, dx, dy: s32)->bool
    {
        let x = cast(s32, mbX) * 16
        let y = cast(s32, mbY) * 16
        if x + 16 > .width or
           y + 16 > .height or
           x + dx < 0 or
           y + dy < 0 or
           x + dx + 16 > .width or
           y + dy + 16 > .height do
            return false
        let width      = cast(u64, .width)
        let current    = frame.luma()
        let uv         = frame.chroma()
        let previousUv = width * cast(u64, .height)
        for row in 16'u64
        {
            let currentStart = (cast(u64, y) + row) * width + cast(u64, x)
            let priorStart   = (cast(u64, y + dy) + row) * width + cast(u64, x + dx)
            for column in 16'u64 where current[currentStart + column] != .previous[priorStart + column] do
                return false
        }

        for row in 8'u64
        {
            let currentStart = (cast(u64, y) / 2 + row) * width + cast(u64, x)
            let priorStart   = (cast(u64, y + dy) / 2 + row) * width + cast(u64, x + dx)
            for column in 16'u64 where uv[currentStart + column] != .previous[previousUv + priorStart + column] do
                return false
        }

        return true
    }

    mtd const findMotion(frame: const *Nv12Frame, mbX, mbY: u32, prediction: EncoderMotion, same: bool, result: *EncoderMotion)->bool
    {
        if prediction.x % 4 == 0 and
           prediction.y % 4 == 0 and
           prediction.x % 8 == 0 and
           prediction.y % 8 == 0 and
           ((prediction.x != 0 or prediction.y != 0 or same) and
            .matchesMotion(frame, mbX, mbY, prediction.x / 4, prediction.y / 4))
        {
            result[] = {prediction.x, prediction.y, true}
            return true
        }

        if (prediction.x != 0 or prediction.y != 0) and
           same and
           .matchesMotion(frame, mbX, mbY, 0, 0)
        {
            result[] = {0, 0, true}
            return true
        }

        // Common diagonal desktop scroll: a tile is copied from its previous position.
        if .matchesMotion(frame, mbX, mbY, -16, -8)
        {
            result[] = {-64, -32, true}
            return true
        }

        for index in 16'u64
        {
            let dx = MotionOffsets[index, 0]
            let dy = MotionOffsets[index, 1]
            if .matchesMotion(frame, mbX, mbY, dx, dy)
            {
                result[] = {dx * 4, dy * 4, true}
                return true
            }
        }

        return false
    }

    mtd buildConfig()
    {
        var sps: EncoderBits
        sps.byte(66)        // Baseline profile.
        sps.byte(0xC0)      // Constrained baseline.
        sps.byte(52)        // Level 5.2.
        sps.unsigned(0)     // seq_parameter_set_id.
        sps.unsigned(4)     // Eight-bit frame_num.
        sps.unsigned(2)     // Picture order follows frame_num.
        sps.unsigned(1)     // One reference picture.
        sps.bit(0)          // No frame_num gaps.
        sps.unsigned(.mbWidth - 1)
        sps.unsigned(.mbHeight - 1)
        sps.bit(1)     // Progressive frames.
        sps.bit(1)     // direct_8x8_inference_flag.
        let cropRight  = .mbWidth * 16 != cast(u32, .width)
        let cropBottom = .mbHeight * 16 != cast(u32, .height)
        sps.bit(cast(u32, cropRight or cropBottom))
        if cropRight or cropBottom
        {
            sps.unsigned(0)
            sps.unsigned((.mbWidth * 16 - cast(u32, .width)) / 2)
            sps.unsigned(0)
            sps.unsigned((.mbHeight * 16 - cast(u32, .height)) / 2)
        }

        sps.bit(1)         // VUI carries the NV12 colour matrix.
        sps.bit(0)         // No sample aspect ratio.
        sps.bit(0)         // No overscan signal.
        sps.bit(1)         // Video signal type is present.
        sps.bits(5, 3)     // Video format unspecified.
        sps.bit(0)         // Studio range.
        sps.bit(1)         // Colour description is present.
        sps.bits(1, 8)     // BT.709 colour primaries.
        sps.bits(1, 8)     // BT.709 transfer characteristic.
        sps.bits(1, 8)     // BT.709 matrix coefficients.
        sps.bit(0)         // No chroma sample location.
        sps.bit(0)         // No timing information.
        sps.bit(0)         // No NAL HRD.
        sps.bit(0)         // No VCL HRD.
        sps.bit(0)         // No picture timing SEI.
        sps.bit(0)         // No bitstream restriction.
        sps.trailing()

        var pps: EncoderBits
        pps.unsigned(0)     // pic_parameter_set_id.
        pps.unsigned(0)     // seq_parameter_set_id.
        pps.bit(0)          // CAVLC.
        pps.bit(0)          // No bottom-field order count.
        pps.unsigned(0)     // One slice group.
        pps.unsigned(0)     // One L0 reference.
        pps.unsigned(0)     // One L1 reference.
        pps.bit(0)          // No weighted prediction.
        pps.bits(0, 2)
        pps.unsigned(0)     // pic_init_qp_minus26.
        pps.unsigned(0)     // pic_init_qs_minus26.
        pps.unsigned(0)     // chroma_qp_index_offset.
        pps.bit(1)          // Slice deblocking control present.
        pps.bit(0)          // Intra prediction not constrained.
        pps.bit(0)          // No redundant pictures.
        pps.trailing()

        var sequence: Array'u8
        var picture:  Array'u8
        appendEncoderNal(&sequence, 0x67, sps.bytes.toSlice())
        appendEncoderNal(&picture, 0x68, pps.bytes.toSlice())
        let sequenceNal = sequence.toSlice()[4 until sequence.count]
        let pictureNal  = picture.toSlice()[4 until picture.count]
        .config.add(1'u8)
        .config.add(66'u8)
        .config.add(0xC0'u8)
        .config.add(52'u8)
        .config.add(0xFF'u8)
        .config.add(0xE1'u8)
        .config.add(cast(u8, sequenceNal.count >> 8))
        .config.add(cast(u8, sequenceNal.count))
        .config.add(sequenceNal)
        .config.add(1'u8)
        .config.add(cast(u8, pictureNal.count >> 8))
        .config.add(cast(u8, pictureNal.count))
        .config.add(pictureNal)
    }

    mtd const unchanged(frame: const *Nv12Frame, mbX, mbY: u32, firstDifferent: *u32)->bool
    {
        if .previous.isEmpty() do
            return false
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        let luma   = frame.luma()
        let uv     = frame.chroma()
        let x      = cast(u64, mbX) * 16
        let y      = cast(u64, mbY) * 16
        if x + 16 <= width and y + 16 <= height
        {
            for row in 16'u64
            {
                let offset = (y + row) * width + x
                if Memory.compare(luma.buffer + offset, .previous.storage() + offset, 16) != 0
                {
                    for column in 16'u64 where luma[offset + column] != .previous[offset + column]
                    {
                        firstDifferent[] = cast(u32, row * 16 + column)
                        return false
                    }
                }
            }

            for row in 8'u64
            {
                let offset = (y / 2 + row) * width + x
                if Memory.compare(uv.buffer + offset,
                                  .previous.storage() + width * height + offset,
                                  16) != 0
                {
                    firstDifferent[] = 256
                    return false
                }
            }

            return true
        }

        for row in 16'u64
        {
            for column in 16'u64
            {
                let x      = Math.min(cast(u64, mbX) * 16 + column, width - 1)
                let y      = Math.min(cast(u64, mbY) * 16 + row, height - 1)
                let offset = y * width + x
                if luma[offset] != .previous[offset]
                {
                    firstDifferent[] = cast(u32, row * 16 + column)
                    return false
                }
            }
        }

        for row in 8'u64
        {
            for column in 8'u64
            {
                let x      = Math.min(cast(u64, mbX) * 8 + column, width / 2 - 1)
                let y      = Math.min(cast(u64, mbY) * 8 + row, height / 2 - 1)
                let offset = y * width + x * 2
                if uv[offset] != .previous[width * height + offset] or
                   uv[offset + 1] != .previous[width * height + offset + 1]
                {
                    firstDifferent[] = 256
                    return false
                }
            }
        }

        return true
    }

    mtd const writePcm(bits: *EncoderBits, frame: const *Nv12Frame, mbX, mbY: u32)
    {
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        let luma   = frame.luma()
        let uv     = frame.chroma()
        if cast(u64, mbX) * 16 + 16 <= width and
           cast(u64, mbY) * 16 + 16 <= height
        {
            for row in 16'u64
            {
                let offset = (cast(u64, mbY) * 16 + row) * width + cast(u64, mbX) * 16
                bits.alignedBytes(luma[offset until offset + 16])
            }
        }
        else
        {
            var paddedLuma: [256] u8
            for row in 16'u64
            {
                for column in 16'u64
                {
                    let x = Math.min(cast(u64, mbX) * 16 + column, width - 1)
                    let y = Math.min(cast(u64, mbY) * 16 + row, height - 1)
                    paddedLuma[row * 16 + column] = luma[y * width + x]
                }
            }

            bits.alignedBytes(Swag.makeSlice(&paddedLuma[0], paddedLuma.count))
        }

        for plane in 2'u64
        {
            var planar: [64] u8
            for row in 8'u64
            {
                for column in 8'u64
                {
                    let x = Math.min(cast(u64, mbX) * 8 + column, width / 2 - 1)
                    let y = Math.min(cast(u64, mbY) * 8 + row, height / 2 - 1)
                    planar[row * 8 + column] = uv[y * width + x * 2 + plane]
                }
            }

            bits.alignedBytes(Swag.makeSlice(&planar[0], planar.count))
        }
    }
}
