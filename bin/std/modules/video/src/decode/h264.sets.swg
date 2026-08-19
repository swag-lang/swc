#global namespace H264
#global internal

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

// One sequence parameter set, reduced to what a progressive 8-bit 4:2:0 decoder uses.
struct Sps
{
    valid:               bool
    profile:             u8
    pocType:             u8
    log2MaxFrameNum:     u32
    log2MaxPocLsb:       u32
    deltaPocAlwaysZero:  bool
    offsetForNonRefPic:  s32
    offsetForTopToBottom: s32
    pocCycle:            Array's32     // offset_for_ref_frame of picture-order type 1.
    maxRefFrames:        u32
    gapsAllowed:         bool
    mbWidth:             s32           // Coded width, in macroblocks.
    mbHeight:            s32           // Coded height, in macroblocks.
    frameMbsOnly:        bool
    direct8x8Inference:  bool
    cropLeft:            s32           // Cropping, in luma pixels.
    cropRight:           s32
    cropTop:             s32
    cropBottom:          s32
    hasScaling:          bool
    scaling4:            [96] u8      // Six weight lists of Table 7-2, in zig-zag scan order.
    scaling8:            [128] u8     // Intra then inter 8x8 weight lists, in zig-zag scan order.
}

// One picture parameter set, with its dequantization tables resolved against its sequence set.
struct Pps
{
    valid:                 bool
    spsId:                 u32
    cabac:                 bool
    picOrderPresent:       bool
    defaultRefCount:       [2] u32
    weightedPred:          bool
    weightedBipredIdc:     u32
    initQp:                s32
    chromaQpOffset:        [2] s32
    deblockControlPresent: bool
    constrainedIntra:      bool
    redundantPicCntPresent: bool
    transform8x8:          bool

    // Dequantization multiplier per list, QP, and raster position, with the `QP / 6` shift
    // folded in: a 4x4 level dequantizes as `(level * dequant4 + 8) >> 4`, an 8x8 one as
    // `(level * dequant8 + 32) >> 6`. Lists follow Table 7-2: intra Y, Cb, Cr then inter Y,
    // Cb, Cr for 4x4, and intra then inter for 8x8.
    dequant4:              [6, 52, 16] u32
    dequant8:              [2, 52, 64] u32
}

// Parses one `scaling_list` syntax structure into `list`, reporting the use-default escape.
private func parseScalingList(bits: *BitReader, list: [..] u8)->bool
{
    var lastScale  = 8's32
    var nextScale  = 8's32
    var useDefault = false
    for index in @countof(list)
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
    for index in @countof(list) do
        list[index] = values[index]
}

// Parses the eight scaling lists shared by the sequence and picture sets.
//
// `fromSps` selects the fall-back rule: an absent sequence list falls back to the default
// matrices, while an absent picture list falls back to the active sequence lists.
private func parseScalingMatrices(bits: *BitReader, sps: *Sps, scaling4: [..] u8, scaling8: [..] u8, fromSps: bool)
{
    for listIndex in 8'u64
    {
        let is8x8      = listIndex >= 6
        let list4      = is8x8 ? scaling4[0 until 16] : scaling4[listIndex * 16 until listIndex * 16 + 16]
        let list8      = is8x8 ? scaling8[(listIndex - 6) * 64 until (listIndex - 5) * 64] : scaling8[0 until 64]
        let present    = bits.bit() != 0
        var useDefault = false
        if present do
            useDefault = parseScalingList(bits, is8x8 ? list8 : list4)

        if present and !useDefault do
            continue

        // Fall-back rules A and B of Table 7-2, with the in-stream default escape folded in.
        let defaults4 = listIndex < 3 ? DefaultScaling4[0 until 16] : DefaultScaling4[16 until 32]
        switch listIndex
        {
        case 0, 3:
            if useDefault or fromSps do
                setList(list4, defaults4)
            else do
                setList(list4, sps.scaling4[listIndex * 16 until listIndex * 16 + 16])

        case 6, 7:
            if useDefault or fromSps do
                setList(list8, DefaultScaling8[(listIndex - 6) * 64 until (listIndex - 5) * 64])
            else do
                setList(list8, sps.scaling8[(listIndex - 6) * 64 until (listIndex - 5) * 64])

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
        bits.skip(8)                          // Constraint flags and reserved bits.
        bits.skip(8)                          // level_idc.
        discard bits.ue()                     // seq_parameter_set_id, checked by the caller.

        // Every list weight defaults to 16, the flat matrix.
        for &value in .scaling4 do
            value[] = 16
        for &value in .scaling8 do
            value[] = 16

        var chromaFormat = 1'u32
        if .profile == 100 or .profile == 110 or .profile == 122 or .profile == 244 or .profile == 44 or .profile == 83 or .profile == 86 or .profile == 118 or .profile == 128 or .profile == 138 or .profile == 139 or .profile == 134 or .profile == 135
        {
            chromaFormat = bits.ue()
            if chromaFormat == 3 do
                bits.skip(1)                  // separate_colour_plane_flag.
            let bitDepthLuma   = bits.ue() + 8
            let bitDepthChroma = bits.ue() + 8
            let transformBypass = bits.bit()
            if chromaFormat != 1 do
                fail UnsupportedFormatError{"video decoder only supports 4:2:0 H.264 streams"}
            if bitDepthLuma != 8 or bitDepthChroma != 8 do
                fail UnsupportedFormatError{"video decoder only supports 8-bit H.264 streams"}
            if transformBypass do
                fail UnsupportedFormatError{"video decoder does not support lossless H.264 transform bypass"}

            .hasScaling = bits.bit() != 0
            if .hasScaling do
                parseScalingMatrices(&bits, me, .scaling4, .scaling8, fromSps: true)
        }

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

        let widthInMbs        = bits.ue() + 1
        let heightInMapUnits  = bits.ue() + 1
        .frameMbsOnly = bits.bit() != 0
        if !.frameMbsOnly do
            fail UnsupportedFormatError{"video decoder does not support interlaced H.264 streams"}
        if widthInMbs > 1024 or heightInMapUnits > 1024 do
            fail UnsupportedFormatError{"H.264 frame size exceeds the decoder's limits"}
        .mbWidth  = cast(s32) widthInMbs
        .mbHeight = cast(s32) heightInMapUnits

        .direct8x8Inference = bits.bit() != 0
        if bits.bit()
        {
            // Cropping is expressed in 4:2:0 chroma units; keep luma pixels.
            .cropLeft   = cast(s32) bits.ue() * 2
            .cropRight  = cast(s32) bits.ue() * 2
            .cropTop    = cast(s32) bits.ue() * 2
            .cropBottom = cast(s32) bits.ue() * 2
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

        discard bits.ue()                     // pic_parameter_set_id, checked by the caller.
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
        discard bits.se()                     // pic_init_qs_minus26, SP/SI slices only.
        .chromaQpOffset[0] = bits.se()
        .chromaQpOffset[1] = .chromaQpOffset[0]
        .deblockControlPresent  = bits.bit() != 0
        .constrainedIntra       = bits.bit() != 0
        .redundantPicCntPresent = bits.bit() != 0

        var scaling4 = sps.scaling4
        var scaling8 = sps.scaling8
        if bits.moreData()
        {
            .transform8x8 = bits.bit() != 0
            if bits.bit() do
                parseScalingMatrices(&bits, sps, scaling4, scaling8, fromSps: false)
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
                    let raster = cast(u64) Zigzag4[scan]
                    let x      = raster & 3
                    let y      = raster >> 2
                    let posClass = (x & 1) + (y & 1)
                    .dequant4[list, qp, raster] = (cast(u32) scaling4[list * 16 + scan] * cast(u32) Dequant4Scale[mod6 * 3 + posClass]) << shift
                }
            }
        }

        for list in 2'u64
        {
            for qp in 52'u64
            {
                let shift = cast(u32) (qp / 6)
                let mod6  = qp % 6
                for scan in 64'u64
                {
                    let raster = cast(u64) Zigzag8[scan]
                    let x      = raster & 7
                    let y      = raster >> 3
                    let posClass = cast(u64) Dequant8ScaleClass[(x & 3) + (y & 3) * 4]
                    .dequant8[list, qp, raster] = (cast(u32) scaling8[list * 64 + scan] * cast(u32) Dequant8Scale[mod6 * 6 + posClass]) << shift
                }
            }
        }
    }
}
