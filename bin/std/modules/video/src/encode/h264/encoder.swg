//! Format: H.264/AVC constrained-baseline encoder.
//! Supported: Progressive NV12 pictures, flat intra blocks, exact PCM blocks, integer-pixel motion copies, P-skip, and periodic IDR pictures.
//! Not supported: Transform coding, rate control, B pictures, and real-time high-resolution capture.
//! Role: This file supplies encoded packets without an external codec or platform encoder.
//
#global namespace H264
#global export

using Core, Core.Errors

private struct EncoderBits
{
    bytes:   Array'u8
    current: u8
    used:    u32
}

private struct EncoderMotion
{
    x:     s32
    y:     s32
    inter: bool
}

private const MotionOffsets: [16, 2] s32 = [
    [0, -2], [0, 2], [0, -4], [0, 4], [0, -8], [0, 8],
    [0, -16], [0, 16], [0, -32], [0, 32],
    [-16, 0], [16, 0], [-32, 0], [32, 0],
    [-16, -16], [16, 16]]

private impl EncoderBits
{
    mtd bit(value: u32)
    {
        .current = cast(u8, (cast(u32, .current) << 1) | (value & 1))
        .used += 1
        if .used == 8
        {
            .bytes.add(.current)
            .current = 0
            .used    = 0
        }
    }

    mtd bits(value: u32, count: u32)
    {
        var remaining = count
        while remaining
        {
            remaining -= 1
            .bit(value >> remaining)
        }
    }

    mtd unsigned(value: u32)
    {
        let code = value + 1
        var size = 0'u32
        var copy = code
        while copy
        {
            size += 1
            copy >>= 1
        }
        for size - 1 do
            .bit(0)
        .bits(code, size)
    }

    mtd signed(value: s32)
    {
        .unsigned(cast(u32, value > 0 ? value * 2 - 1 : -value * 2))
    }

    mtd alignZero()
    {
        while .used do
            .bit(0)
    }

    mtd trailing()
    {
        .bit(1)
        .alignZero()
    }

    mtd byte(value: u8)
    {
        Swag.assert(not .used)
        .bytes.add(value)
    }

    mtd alignedBytes(values: const [..] u8)
    {
        Swag.assert(not .used)
        .bytes.add(values)
    }
}

// Encodes NV12 pictures as H.264 access units for a fragmented MP4 writer.
//
// This portable first stage codes flat intra blocks with no residual, copies exact integer-pixel
// motion blocks in P pictures, uses P-skip for unchanged blocks, and codes remaining changes
// with I_PCM. It is useful for scrolling and interoperability, but uncompressed remaining blocks
// are not suitable for arbitrary high-motion 1080p60 recording. The result borrows the encoder's
// packet storage until the next call to encode. The AVC configuration remains valid for the
// encoder's lifetime and uses four-byte NAL lengths.
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
        width:          s32
        height:         s32
        mbWidth:        u32
        mbHeight:       u32
        keyInterval:    u32
        frameNumber:    u32
        framesSinceKey: u32
        previousEnd:    u64
        hasFrame:       bool
    }
}

impl Encoder
{
    // Creates an encoder for even NV12 dimensions and an IDR interval in frames.
    //
    // The image may be cropped within its final macroblock. Dimensions are limited to
    // 4096 pixels per side and 36864 macroblocks, matching H.264 level 5.2 frame size.
    // The interval is 1 to 255 pictures. A new encoder starts with an IDR picture.
    func create(width, height: s32, keyInterval: u32 = 60)->Encoder fail
    {
        if width <= 0 or height <= 0 or width > 4096 or height > 4096 or
           width % 2 or height % 2 or not keyInterval or keyInterval > 255 do
            fail BadParameterError{"H.264 encoder needs even dimensions and an IDR interval of 1 to 255"}
        let mbWidth  = cast(u32, (width + 15) / 16)
        let mbHeight = cast(u32, (height + 15) / 16)
        if mbWidth * mbHeight > 36_864 do
            fail UnsupportedFormatError{"H.264 encoder picture exceeds level 5.2 frame size"}

        with var result: #returntype
        {
            .width       = width
            .height      = height
            .mbWidth     = mbWidth
            .mbHeight    = mbHeight
            .keyInterval = keyInterval
        }
        result.buildConfig()
        return result
    }

    // Borrows the AVC decoder configuration until this encoder is destroyed.
    mtd const decoderConfig()->const [..] u8 => .config.toSlice()

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
        if not duration or decodeTime > Swag.U64.Max - duration or
           (.hasFrame and decodeTime < .previousEnd) do
            fail BadParameterError{"H.264 encoder packet timing is invalid"}

        let key = not .hasFrame or .framesSinceKey >= .keyInterval
        var bits: EncoderBits
        bits.unsigned(0)                     // first_mb_in_slice.
        bits.unsigned(key ? 2 : 0)           // I or P slice.
        bits.unsigned(0)                     // pic_parameter_set_id.
        bits.bits(key ? 0 : .frameNumber, 8)
        if key do
            bits.unsigned(0)                 // idr_pic_id.
        else
        {
            bits.bit(0)                      // num_ref_idx_active_override_flag.
            bits.bit(0)                      // ref_pic_list_modification_flag_l0.
        }
        if key
        {
            bits.bit(0)                      // no_output_of_prior_pics_flag.
            bits.bit(0)                      // long_term_reference_flag.
        }
        else do
            bits.bit(0)                      // adaptive_ref_pic_marking_mode_flag.
        bits.unsigned(0)                     // slice_qp_delta = 0.
        bits.unsigned(1)                     // Disable deblocking; PCM and skip stay exact.

        var skipped = 0'u32
        var motions: Array'EncoderMotion
        var pcm: Array'bool
        pcm.resize(cast(u64, .mbWidth) * .mbHeight)
        for &value in pcm do
            value[] = false
        if not key
        {
            motions.resize(cast(u64, .mbWidth) * cast(u64, .mbHeight))
            for &value in motions do
                value[] = {}
        }
        for mbY in .mbHeight
        {
            for mbX in .mbWidth
            {
                let motionIndex = cast(u64, mbY) * .mbWidth + mbX
                let prediction = key ? EncoderMotion{} : .predictMotion(motions.toSlice(), mbX, mbY)
                if not key and .unchanged(frame, mbX, mbY) and
                   .skipMotionIsZero(motions.toSlice(), mbX, mbY)
                {
                    skipped += 1
                    motions[motionIndex] = {0, 0, true}
                    continue
                }
                if not key do
                    bits.unsigned(skipped)
                if .flatIntra(frame, mbX, mbY)
                {
                    bits.unsigned(key ? 3 : 8) // Intra_16x16 DC, no coded AC/chroma.
                    bits.unsigned(0)           // Chroma DC prediction.
                    bits.signed(0)             // No QP change.
                    .writeEmptyIntraDc(&bits, pcm.toSlice(), mbX, mbY)
                    skipped = 0
                    continue
                }
                if not key
                {
                    var motion: EncoderMotion
                    if .findMotion(frame, mbX, mbY, prediction, &motion)
                    {
                        bits.unsigned(0)             // P_L0_16x16.
                        bits.signed(motion.x - prediction.x)
                        bits.signed(motion.y - prediction.y)
                        bits.unsigned(0)             // No residual coefficients.
                        motions[motionIndex] = motion
                        skipped = 0
                        continue
                    }
                }
                bits.unsigned(key ? 25 : 30)   // I_PCM in I/P slice type spaces.
                bits.alignZero()
                .writePcm(&bits, frame, mbX, mbY)
                pcm[motionIndex] = true
                skipped = 0
            }
        }
        if not key and skipped do
            bits.unsigned(skipped)
        bits.trailing()

        var packet: Array'u8
        appendEncoderNal(&packet, key ? 0x65 : 0x41, bits.bytes.toSlice())
        .packet   = #move packet
        .previous.clear()
        .previous.add(frame.bytes.toSlice())
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
}

private impl Encoder
{
    // A constant 16x16 block is represented by Intra_16x16 DC without coefficients when
    // every available top and left boundary has the same samples in all three planes.
    mtd const flatIntra(frame: const *Nv12Frame, mbX, mbY: u32)->bool
    {
        let x = cast(u64, mbX) * 16
        let y = cast(u64, mbY) * 16
        let width = cast(u64, .width)
        let height = cast(u64, .height)
        if not mbX and not mbY do
            return false
        let luma = frame.luma()
        let chroma = frame.chroma()
        let valueY = luma[y * width + x]
        let valueU = chroma[y / 2 * width + x]
        let valueV = chroma[y / 2 * width + x + 1]
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
                let offset = sourceY * width + sourceX
                if chroma[offset] != valueU or chroma[offset + 1] != valueV do
                    return false
            }
        }
        if mbY
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

    mtd const writeEmptyIntraDc(bits: *EncoderBits, pcm: const [..] bool, mbX, mbY: u32)
    {
        let left = mbX > 0 ? (pcm[cast(u64, mbY) * .mbWidth + mbX - 1] ? 16'u32 : 0) : 0
        let top = mbY > 0 ? (pcm[cast(u64, mbY - 1) * .mbWidth + mbX] ? 16'u32 : 0) : 0
        let nC = mbX > 0 and mbY > 0 ? (left + top + 1) / 2 : left + top
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
    mtd const predictMotion(motions: const [..] EncoderMotion, mbX, mbY: u32)->EncoderMotion
    {
        let x = cast(s32, mbX)
        let y = cast(s32, mbY)
        let a = .motionAt(motions, x - 1, y)
        let b = .motionAt(motions, x, y - 1)
        var c = .motionAt(motions, x + 1, y - 1)
        if x + 1 >= cast(s32, .mbWidth) do
            c = .motionAt(motions, x - 1, y - 1)

        let availableA = x > 0
        let availableB = y > 0
        let availableC = y > 0 and (x + 1 < cast(s32, .mbWidth) or x > 0)
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

    mtd const skipMotionIsZero(motions: const [..] EncoderMotion, mbX, mbY: u32)->bool
    {
        if mbX == 0 or mbY == 0 do
            return true
        let a = .motionAt(motions, cast(s32, mbX) - 1, cast(s32, mbY))
        let b = .motionAt(motions, cast(s32, mbX), cast(s32, mbY) - 1)
        if a.inter and a.x == 0 and a.y == 0 do
            return true
        if b.inter and b.x == 0 and b.y == 0 do
            return true
        let predicted = .predictMotion(motions, mbX, mbY)
        return predicted.x == 0 and predicted.y == 0
    }

    // Tests exact whole-pixel matches against the previous picture, including interleaved
    // chroma. A motion copy never reaches into a cropped or padded edge macroblock.
    mtd const matchesMotion(frame: const *Nv12Frame, mbX, mbY: u32, dx, dy: s32)->bool
    {
        let x = cast(s32, mbX) * 16
        let y = cast(s32, mbY) * 16
        if x + 16 > .width or y + 16 > .height or x + dx < 0 or y + dy < 0 or
           x + dx + 16 > .width or y + dy + 16 > .height do
            return false
        let width = cast(u64, .width)
        let current = frame.luma()
        let uv = frame.chroma()
        let previousUv = width * cast(u64, .height)
        for row in 16'u64
        {
            let currentStart = (cast(u64, y) + row) * width + cast(u64, x)
            let priorStart = (cast(u64, y + dy) + row) * width + cast(u64, x + dx)
            for column in 16'u64 where current[currentStart + column] != .previous[priorStart + column] do
                return false
        }
        for row in 8'u64
        {
            let currentStart = (cast(u64, y) / 2 + row) * width + cast(u64, x)
            let priorStart = (cast(u64, y + dy) / 2 + row) * width + cast(u64, x + dx)
            for column in 16'u64 where uv[currentStart + column] != .previous[previousUv + priorStart + column] do
                return false
        }
        return true
    }

    mtd const findMotion(frame: const *Nv12Frame, mbX, mbY: u32,
                         prediction: EncoderMotion, result: *EncoderMotion)->bool
    {
        if prediction.x % 4 == 0 and prediction.y % 4 == 0 and
           prediction.x % 8 == 0 and prediction.y % 8 == 0 and
           .matchesMotion(frame, mbX, mbY, prediction.x / 4, prediction.y / 4)
        {
            result[] = {prediction.x, prediction.y, true}
            return true
        }
        if .matchesMotion(frame, mbX, mbY, 0, 0)
        {
            result[] = {0, 0, true}
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
        sps.byte(66)                         // Baseline profile.
        sps.byte(0xC0)                       // Constrained baseline.
        sps.byte(52)                         // Level 5.2.
        sps.unsigned(0)                      // seq_parameter_set_id.
        sps.unsigned(4)                      // Eight-bit frame_num.
        sps.unsigned(2)                      // Picture order follows frame_num.
        sps.unsigned(1)                      // One reference picture.
        sps.bit(0)                           // No frame_num gaps.
        sps.unsigned(.mbWidth - 1)
        sps.unsigned(.mbHeight - 1)
        sps.bit(1)                           // Progressive frames.
        sps.bit(1)                           // direct_8x8_inference_flag.
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
        sps.bit(1)                           // VUI carries the NV12 colour matrix.
        sps.bit(0)                           // No sample aspect ratio.
        sps.bit(0)                           // No overscan signal.
        sps.bit(1)                           // Video signal type is present.
        sps.bits(5, 3)                       // Video format unspecified.
        sps.bit(0)                           // Studio range.
        sps.bit(1)                           // Colour description is present.
        sps.bits(1, 8)                       // BT.709 colour primaries.
        sps.bits(1, 8)                       // BT.709 transfer characteristic.
        sps.bits(1, 8)                       // BT.709 matrix coefficients.
        sps.bit(0)                           // No chroma sample location.
        sps.bit(0)                           // No timing information.
        sps.bit(0)                           // No NAL HRD.
        sps.bit(0)                           // No VCL HRD.
        sps.bit(0)                           // No picture timing SEI.
        sps.bit(0)                           // No bitstream restriction.
        sps.trailing()

        var pps: EncoderBits
        pps.unsigned(0)                      // pic_parameter_set_id.
        pps.unsigned(0)                      // seq_parameter_set_id.
        pps.bit(0)                           // CAVLC.
        pps.bit(0)                           // No bottom-field order count.
        pps.unsigned(0)                      // One slice group.
        pps.unsigned(0)                      // One L0 reference.
        pps.unsigned(0)                      // One L1 reference.
        pps.bit(0)                           // No weighted prediction.
        pps.bits(0, 2)
        pps.unsigned(0)                      // pic_init_qp_minus26.
        pps.unsigned(0)                      // pic_init_qs_minus26.
        pps.unsigned(0)                      // chroma_qp_index_offset.
        pps.bit(1)                           // Slice deblocking control present.
        pps.bit(0)                           // Intra prediction not constrained.
        pps.bit(0)                           // No redundant pictures.
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

    mtd const unchanged(frame: const *Nv12Frame, mbX, mbY: u32)->bool
    {
        if .previous.isEmpty() do
            return false
        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        let luma   = frame.luma()
        let uv     = frame.chroma()
        for row in 16'u64
        {
            for column in 16'u64
            {
                let x = Math.min(cast(u64, mbX) * 16 + column, width - 1)
                let y = Math.min(cast(u64, mbY) * 16 + row, height - 1)
                let offset = y * width + x
                if luma[offset] != .previous[offset] do
                    return false
            }
        }
        for row in 8'u64
        {
            for column in 8'u64
            {
                let x = Math.min(cast(u64, mbX) * 8 + column, width / 2 - 1)
                let y = Math.min(cast(u64, mbY) * 8 + row, height / 2 - 1)
                let offset = y * width + x * 2
                if uv[offset] != .previous[width * height + offset] or
                   uv[offset + 1] != .previous[width * height + offset + 1] do
                    return false
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

// Writes an escaped NAL with MP4's four-byte length prefix.
private func appendEncoderNal(packet: *Array'u8, header: u8, payload: const [..] u8)
{
    let start = packet.count
    for 4 do
        packet.add(0'u8)
    packet.add(header)
    var zeros = 0'u32
    for value in payload
    {
        if zeros == 2 and value <= 3
        {
            packet.add(3'u8)
            zeros = 0
        }
        packet.add(value)
        zeros = value == 0 ? zeros + 1 : 0
        if zeros > 2 do
            zeros = 2
    }
    let length = cast(u32, packet.count - start - 4)
    packet[start]     = cast #wrap(u8, length >> 24)
    packet[start + 1] = cast #wrap(u8, length >> 16)
    packet[start + 2] = cast #wrap(u8, length >> 8)
    packet[start + 3] = cast #wrap(u8, length)
}
