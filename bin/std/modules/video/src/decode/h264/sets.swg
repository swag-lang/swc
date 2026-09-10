#global namespace H264
#global internal

//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 and 4:4:4 Baseline, Main, High, and High 4:4:4 Predictive streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, 4:2:2 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns sequence and picture parameter-set parsing and capability checks.
//

using Core, Core.Errors

// 4x4 zig-zag scan: scan position to raster position.
const Zigzag4: [16] u8 = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15]

// 8x8 zig-zag scan: scan position to raster position.
const Zigzag8: [64] u8 = [
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
    28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37,
    44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47,
    55, 62, 63]

// Where each coefficient a residual block codes lands in its block, by the shape of the block.
//
// The entropy decoders store every level at its raster position, already dequantized, so the
// inverse transform reads the block as it is. A DC block keeps its own order, since it goes
// through a transform of its own before it is scaled. An AC block codes the zigzag scan from
// its second position, the first being the DC that reconstruction adds.
const ResidualOrderDc  = 0'u64
const ResidualOrder4x4 = 16'u64
const ResidualOrderAc  = 32'u64
const ResidualOrder8x8 = 48'u64
const ResidualOrder: [112] u8 = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15,
    1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15, 0,
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
    28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37,
    44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47,
    55, 62, 63]

// Scales one coefficient level by its factor, sections 8.5.12.1 and 8.5.13.1: `shift` is 4
// for a 4x4 block and 6 for an 8x8 one.
#[Swag.Inline]
func dequantLevel(level: s32, scale: u32, shift: u32)->s16
{
    return cast(s16) clampS32((level * cast(s32) scale + (1's32 << (shift - 1))) >> shift, -32768, 32767)
}

// Stores the levels of one block, decoded in scan order, at their raster positions, dequantized
// with one row of the scaling table.
func storeLevels(levels: const [*] s16, count: u32, coeffs: [*] s16, order: u64, scale: [*] u32, shift: u32)
{
    for index in cast(u64) count
    {
        let level = cast(s32) levels[index]
        if level == 0 do
            continue
        let raster = cast(u64) ResidualOrder[order + index]
        coeffs[raster] = dequantLevel(level, scale[raster], shift)
    }
}

// One sequence parameter set, reduced to what a progressive 8-bit decoder uses.
struct Sps
{
    valid:   bool
    profile: u8

    // `chroma_format_idc`: 1 for 4:2:0, 3 for 4:4:4. It is the one number the rest of the
    // decoder reads to know whether a chroma plane is half the picture or all of it, and in
    // 4:4:4 whether a colour plane is coded like luma rather than with the chroma syntax.
    chromaFormat: u8

    pocType:              u8
    log2MaxFrameNum:      u32
    log2MaxPocLsb:        u32
    deltaPocAlwaysZero:   bool
    offsetForNonRefPic:   s32
    offsetForTopToBottom: s32
    pocCycle:             Array's32     // offset_for_ref_frame of picture-order type 1.
    maxRefFrames:         u32
    gapsAllowed:          bool
    mbWidth:              s32     // Coded width, in macroblocks.
    mbHeight:             s32     // Coded height, in macroblocks.
    frameMbsOnly:         bool
    direct8x8Inference:   bool
    cropLeft:             s32     // Cropping, in luma pixels.
    cropRight:            s32
    cropTop:              s32
    cropBottom:           s32
    hasScaling:           bool
    scaling4:             [96] u8     // Six weight lists of Table 7-2, in zig-zag scan order.

    // 8x8 weight lists of Table 7-2, in zig-zag scan order: intra then inter for luma, and in
    // 4:4:4 the same pair for Cb and then for Cr. A 4:2:0 stream leaves the last four flat.
    scaling8: [384] u8
}

// One picture parameter set, with its dequantization tables resolved against its sequence set.
struct Pps
{
    valid:                  bool
    spsId:                  u32
    cabac:                  bool
    picOrderPresent:        bool
    defaultRefCount:        [2] u32
    weightedPred:           bool
    weightedBipredIdc:      u32
    initQp:                 s32
    chromaQpOffset:         [2] s32
    deblockControlPresent:  bool
    constrainedIntra:       bool
    redundantPicCntPresent: bool
    transform8x8:           bool

    // Dequantization multiplier per list, QP, and raster position, with the `QP / 6` shift
    // folded in: a 4x4 level dequantizes as `(level * dequant4 + 8) >> 4`, an 8x8 one as
    // `(level * dequant8 + 32) >> 6`. Lists follow Table 7-2: intra Y, Cb, Cr then inter Y,
    // Cb, Cr for 4x4, and intra then inter per plane for 8x8.
    dequant4: [6, 52, 16] u32
    dequant8: [6, 52, 64] u32
}

// Parses one `scaling_list` syntax structure into `list`, reporting the use-default escape.
private func parseScalingList(bits: *BitReader, list: [..] u8)->bool
{
    var lastScale  = 8's32
    var nextScale  = 8's32
    var useDefault = false
    for index in list.count
    {
        if nextScale != 0
        {
            let delta = bits.se()
            nextScale = (lastScale + delta + 256) % 256
            if index == 0 and nextScale == 0 do
                useDefault = true
        }

        list[index] = cast(u8) (nextScale == 0 ? lastScale : nextScale)
        lastScale   = cast(s32) list[index]
    }

    return useDefault
}

// Fills `list` with `values`.
private func setList(list: [..] u8, values: const [..] u8)
{
    for index in list.count do
        list[index] = values[index]
}

// Parses the scaling lists shared by the sequence and picture sets.
//
// A 4:2:0 stream carries eight lists, six 4x4 and two 8x8; a 4:4:4 stream carries twelve,
// because its Cb and Cr planes take the 8x8 transform as luma does and so need an intra and an
// inter 8x8 list of their own.
//
// `fromSps` selects the fall-back rule: an absent sequence list falls back to the default
// matrices, while an absent picture list falls back to the active sequence lists.
private func parseScalingMatrices(bits: *BitReader, sps: *Sps, scaling4: [..] u8, scaling8: [..] u8, fromSps: bool, listCount: u64)
{
    for listIndex in listCount
    {
        let is8x8      = listIndex >= 6
        let index8     = is8x8 ? listIndex - 6 : 0
        let list4      = is8x8 ? scaling4[0 until 16] : scaling4[listIndex * 16 until listIndex * 16 + 16]
        let list8      = scaling8[index8 * 64 until index8 * 64 + 64]
        let present    = bits.bit() != 0
        var useDefault = false
        if present do
            useDefault = parseScalingList(bits, is8x8 ? list8 : list4)

        if present and not useDefault do
            continue

        // Fall-back rules A and B of Table 7-2, with the in-stream default escape folded in.
        // An 8x8 list of a colour plane falls back to the list of the same intra or inter kind
        // two places before it, which is the plane before it.
        let defaults4 = listIndex < 3 ? DefaultScaling4[0 until 16] : DefaultScaling4[16 until 32]
        let defaults8 = (index8 & 1) == 0 ? DefaultScaling8[0 until 64] : DefaultScaling8[64 until 128]
        switch
        {
        case listIndex == 0 or listIndex == 3:
            if useDefault or fromSps do
                setList(list4, defaults4)
            else do
                setList(list4, sps.scaling4[listIndex * 16 until listIndex * 16 + 16])

        case listIndex == 6 or listIndex == 7:
            if useDefault or fromSps do
                setList(list8, defaults8)
            else do
                setList(list8, sps.scaling8[index8 * 64 until index8 * 64 + 64])

        case is8x8:
            if useDefault do
                setList(list8, defaults8)
            else do
                setList(list8, scaling8[(index8 - 2) * 64 until (index8 - 1) * 64])

        default:
            if useDefault do
                setList(list4, defaults4)
            else do
                setList(list4, scaling4[(listIndex - 1) * 16 until listIndex * 16])
        }
    }
}

impl Sps
{
    // Parses one sequence parameter set payload.
    mtd parse(payload: const [..] u8) fail
    {
        var bits: BitReader
        bits.init(payload)

        .profile = cast(u8) bits.read(8)
        bits.skip(8)          // Constraint flags and reserved bits.
        bits.skip(8)          // level_idc.
        discard bits.ue()     // seq_parameter_set_id, checked by the caller.

        // Every list weight defaults to 16, the flat matrix.
        for &value in .scaling4 do
            value[] = 16
        for &value in .scaling8 do
            value[] = 16

        var chromaFormat = 1'u32
        if .profile == 100 or .profile == 110 or .profile == 122 or .profile == 244 or .profile == 44 or .profile == 83 or .profile == 86 or .profile == 118 or .profile == 128 or .profile == 138 or .profile == 139 or .profile == 134 or .profile == 135
        {
            chromaFormat = bits.ue()
            var separateColourPlanes = false
            if chromaFormat == 3 do
                separateColourPlanes = bits.bit() != 0
            let bitDepthLuma    = bits.ue() + 8
            let bitDepthChroma  = bits.ue() + 8
            let transformBypass = bits.bit()
            if chromaFormat != 1 and chromaFormat != 3 do
                fail UnsupportedFormatError{"video decoder only supports 4:2:0 and 4:4:4 H.264 streams"}

            // Separate colour planes code each plane as its own monochrome picture with its own
            // slice headers, which is a different picture structure and not merely a sampling.
            if separateColourPlanes do
                fail UnsupportedFormatError{"video decoder does not support H.264 streams coding their colour planes separately"}
            if bitDepthLuma != 8 or bitDepthChroma != 8 do
                fail UnsupportedFormatError{"video decoder only supports 8-bit H.264 streams"}
            if transformBypass do
                fail UnsupportedFormatError{"video decoder does not support lossless H.264 transform bypass"}

            .hasScaling = bits.bit() != 0
            if .hasScaling do
                parseScalingMatrices(&bits, me, .scaling4, .scaling8, fromSps: true, listCount: chromaFormat == 3 ? 12 : 8)
        }

        .chromaFormat = cast(u8) chromaFormat

        .log2MaxFrameNum = bits.ue() + 4
        .pocType         = cast(u8) bits.ue()
        switch .pocType
        {
        case 0:
            .log2MaxPocLsb = bits.ue() + 4
            if .log2MaxPocLsb > 16 do
                fail InvalidFormatError{"H.264 sequence set declares an out-of-range picture-order size"}

        case 1:
            .deltaPocAlwaysZero   = bits.bit() != 0
            .offsetForNonRefPic   = bits.se()
            .offsetForTopToBottom = bits.se()
            let cycleCount = bits.ue()
            if cycleCount > 255 do
                fail InvalidFormatError{"H.264 sequence set declares an out-of-range picture-order cycle"}
            .pocCycle.reserve(cycleCount)
            for cycleCount do
                .pocCycle.add(bits.se())

        case 2:
            break

        default:
            fail InvalidFormatError{"H.264 sequence set declares an unknown picture-order type"}
        }

        .maxRefFrames = bits.ue()
        if .maxRefFrames > 16 do
            fail InvalidFormatError{"H.264 sequence set declares more than sixteen reference frames"}
        .gapsAllowed = bits.bit() != 0

        let widthInMbs       = bits.ue() + 1
        let heightInMapUnits = bits.ue() + 1
        .frameMbsOnly = bits.bit() != 0
        if not .frameMbsOnly do
            fail UnsupportedFormatError{"video decoder does not support interlaced H.264 streams"}
        if widthInMbs > 1024 or heightInMapUnits > 1024 do
            fail UnsupportedFormatError{"H.264 frame size exceeds the decoder's limits"}
        .mbWidth  = cast(s32) widthInMbs
        .mbHeight = cast(s32) heightInMapUnits

        .direct8x8Inference = bits.bit() != 0
        if bits.bit()
        {
            // Cropping is expressed in chroma samples, section 7.4.2.1.1, so a unit is two luma
            // samples on both axes in 4:2:0 and one in 4:4:4, whose chroma planes are the size
            // of luma. Keep luma pixels.
            let unit = 1's32 << .chromaShift()
            .cropLeft   = cast(s32) bits.ue() * unit
            .cropRight  = cast(s32) bits.ue() * unit
            .cropTop    = cast(s32) bits.ue() * unit
            .cropBottom = cast(s32) bits.ue() * unit
        }

        // The VUI that may follow carries nothing this decoder uses.
        if bits.overran do
            fail InvalidFormatError{"H.264 sequence parameter set is truncated"}

        let width  = .mbWidth * 16 - .cropLeft - .cropRight
        let height = .mbHeight * 16 - .cropTop - .cropBottom
        if width <= 0 or height <= 0 do
            fail InvalidFormatError{"H.264 cropping leaves no visible picture"}
        .valid = true
    }

    // Reports whether the sequence codes its two colour planes at the resolution of luma.
    //
    // In 4:4:4 a colour plane is not merely larger: it is predicted, transformed, entropy coded
    // and filtered exactly as luma is, so almost every place that asks this question then takes
    // the luma path with a plane index rather than the chroma one.
    #[Swag.Inline]
    mtd const is444()->bool => .chromaFormat == 3

    // Returns how far a luma coordinate shifts right to address the chroma planes: one in
    // 4:2:0, none in 4:4:4.
    #[Swag.Inline]
    mtd const chromaShift()->s32 => .chromaFormat == 3 ? 0 : 1

    // Returns the visible frame width, in pixels.
    mtd const width()->s32 => .mbWidth * 16 - .cropLeft - .cropRight

    // Returns the visible frame height, in pixels.
    mtd const height()->s32 => .mbHeight * 16 - .cropTop - .cropBottom
}

impl Pps
{
    // Parses one picture parameter set payload and resolves its dequantization tables
    // against `sps`.
    mtd parse(payload: const [..] u8, sps: *Sps) fail
    {
        var bits: BitReader
        bits.init(payload)

        discard bits.ue()     // pic_parameter_set_id, checked by the caller.
        .spsId = bits.ue()
        .cabac = bits.bit() != 0
        .picOrderPresent = bits.bit() != 0

        let sliceGroups = bits.ue() + 1
        if sliceGroups > 1 do
            fail UnsupportedFormatError{"video decoder does not support H.264 slice groups"}

        .defaultRefCount[0] = bits.ue() + 1
        .defaultRefCount[1] = bits.ue() + 1
        if .defaultRefCount[0] > 32 or .defaultRefCount[1] > 32 do
            fail InvalidFormatError{"H.264 picture set declares an out-of-range reference count"}

        .weightedPred      = bits.bit() != 0
        .weightedBipredIdc = bits.read(2)
        .initQp            = 26 + bits.se()
        discard bits.se()     // pic_init_qs_minus26, SP/SI slices only.
        .chromaQpOffset[0]      = bits.se()
        .chromaQpOffset[1]      = .chromaQpOffset[0]
        .deblockControlPresent  = bits.bit() != 0
        .constrainedIntra       = bits.bit() != 0
        .redundantPicCntPresent = bits.bit() != 0

        var scaling4 = sps.scaling4
        var scaling8 = sps.scaling8
        if bits.moreData()
        {
            .transform8x8 = bits.bit() != 0

            // A picture set carries the six 4x4 lists, and the 8x8 ones only when it turns the
            // 8x8 transform on: two of them, or one per colour plane in 4:4:4.
            if bits.bit()
            {
                var listCount = 6'u64
                if .transform8x8 do
                    listCount += sps.is444() ? 6 : 2
                parseScalingMatrices(&bits, sps, scaling4, scaling8, fromSps: false, listCount: listCount)
            }

            .chromaQpOffset[1] = bits.se()
        }

        if bits.overran do
            fail InvalidFormatError{"H.264 picture parameter set is truncated"}
        if .initQp < 0 or .initQp > 51 do
            fail InvalidFormatError{"H.264 picture set declares an out-of-range picture QP"}

        .buildDequant(scaling4, scaling8)
        .valid = true
    }

    // Builds the per-QP dequantization multipliers from the effective weight lists.
    mtd buildDequant(scaling4, scaling8: const [..] u8)
    {
        for list in 6'u64
        {
            for qp in 52'u64
            {
                let shift = cast(u32) (qp / 6)
                let mod6  = qp % 6
                for scan in 16'u64
                {
                    let raster   = cast(u64) Zigzag4[scan]
                    let x        = raster & 3
                    let y        = raster >> 2
                    let posClass = (x & 1) + (y & 1)
                    .dequant4[list, qp, raster] = (cast(u32) scaling4[list * 16 + scan] * cast(u32) Dequant4Scale[mod6 * 3 + posClass]) << shift
                }
            }
        }

        for list in 6'u64
        {
            for qp in 52'u64
            {
                let shift = cast(u32) (qp / 6)
                let mod6  = qp % 6
                for scan in 64'u64
                {
                    let raster   = cast(u64) Zigzag8[scan]
                    let x        = raster & 7
                    let y        = raster >> 3
                    let posClass = cast(u64) Dequant8ScaleClass[(x & 3) + (y & 3) * 4]
                    .dequant8[list, qp, raster] = (cast(u32) scaling8[list * 64 + scan] * cast(u32) Dequant8Scale[mod6 * 6 + posClass]) << shift
                }
            }
        }
    }
}
