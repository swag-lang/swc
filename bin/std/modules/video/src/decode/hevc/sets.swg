//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns video, sequence, and picture parameter-set parsing and capability checks.
//
#global namespace Hevc
#global internal

using Core, Core.Errors

// The largest coding tree block the format allows, and the smallest coding block, in luma samples.
const MaxCtbLog2SizeY = 6'u32
const MinCbLog2SizeAllowed = 3'u32

// A short-term reference picture set holds at most sixteen pictures, clause 7.4.8.
const MaxRefPics = 16'u32

// One short-term reference picture set, after the inter-set prediction of clause 7.4.8 is resolved.
//
// The two halves are kept in the order the standard builds the lists in: `negative` counts down
// from the current picture and `positive` counts up, both by increasing distance.
struct ShortTermRps
{
    negativeCount: u32
    positiveCount: u32
    negativeDelta: [MaxRefPics] s32     // Picture order count deltas, most recent first.
    positiveDelta: [MaxRefPics] s32     // Picture order count deltas, nearest first.
    negativeUsed:  [MaxRefPics] bool    // Whether the current picture may predict from it.
    positiveUsed:  [MaxRefPics] bool
}

impl ShortTermRps
{
    mtd const totalCount()->u32 => .negativeCount + .positiveCount

    // Counts the pictures of this set the current picture is allowed to predict from.
    mtd const usedCount()->u32
    {
        var count = 0'u32
        for index in .negativeCount where .negativeUsed[index] do
            count += 1
        for index in .positiveCount where .positiveUsed[index] do
            count += 1
        return count
    }
}

// The quantization matrices of clause 7.3.4, expanded to the sample grid.
//
// Four transform sizes carry six matrices each, except the 32x32 size where only the two luma
// matrices exist in 4:2:0. A stream that enables scaling lists without sending any uses the
// default matrices of Tables 7-5 and 7-6.
struct ScalingLists
{
    // Indexed as [sizeId][matrixId][coefficient], in up-right diagonal scan order.
    lists: [4, 6, 64] u8

    // The replacement direct-current coefficient of the 16x16 and 32x32 matrices.
    dc: [2, 6] u8
}

impl ScalingLists
{
    // Fills every matrix with the default of Tables 7-5 and 7-6.
    mtd setDefaults()
    {
        for matrixId in 6'u32
        {
            for index in 16'u32 do
                .lists[0, matrixId, index] = DefaultScalingList4x4[index]
            for sizeId in 1 until 4'u32
            {
                for index in 64'u32 do
                    .lists[sizeId, matrixId, index] = matrixId < 3 ? DefaultScalingListIntra[index] : DefaultScalingListInter[index]
            }
        }

        for sizeId in 2'u32
        {
            for matrixId in 6'u32 do
                .dc[sizeId, matrixId] = 16
        }
    }

    // Fills every matrix with sixteen, which is what a stream without scaling lists uses.
    mtd setFlat()
    {
        Memory.set(&.lists, 16, #sizeof(.lists))
        Memory.set(&.dc, 16, #sizeof(.dc))
    }

    // Reads one `scaling_list_data` structure, clause 7.3.4.
    mtd read(reader: *BitReader) fail
    {
        for sizeId in 4'u32
        {
            var matrixId = 0'u32
            while matrixId < 6
            {
                // The 32x32 size carries the two luma matrices only, in every chroma format this
                // decoder reads.
                let step = sizeId == 3 ? 3'u32 : 1'u32
                if reader.bit() == 0
                {
                    // A matrix that predicts from an earlier one, or from the default when the
                    // delta selects itself.
                    let delta = reader.ue()
                    if delta > matrixId / step do
                        fail InvalidFormatError{"HEVC scaling list refers to a matrix that does not precede it"}
                    if delta == 0
                    {
                        .setDefaultMatrix(sizeId, matrixId)
                    }
                    else
                    {
                        let source = matrixId - delta * step
                        for index in 64'u32 do
                            .lists[sizeId, matrixId, index] = .lists[sizeId, source, index]
                        if sizeId > 1 do
                            .dc[sizeId - 2, matrixId] = .dc[sizeId - 2, source]
                    }
                }
                else
                {
                    let count   = sizeId == 0 ? 16'u32 : 64'u32
                    var nextCoef = 8's32
                    if sizeId > 1
                    {
                        let dcMinus8 = reader.se()
                        if dcMinus8 < -7 or dcMinus8 > 247 do
                            fail InvalidFormatError{"HEVC scaling list direct-current coefficient is out of range"}
                        .dc[sizeId - 2, matrixId] = cast(u8) (dcMinus8 + 8)
                        nextCoef                  = dcMinus8 + 8
                    }

                    for index in count
                    {
                        nextCoef = (nextCoef + reader.se() + 256) % 256
                        .lists[sizeId, matrixId, index] = cast(u8) nextCoef
                    }
                }

                matrixId += step
            }
        }

        if reader.overran do
            fail InvalidFormatError{"HEVC scaling list data is truncated"}
    }

    // Restores one matrix to the default of Tables 7-5 and 7-6.
    private mtd setDefaultMatrix(sizeId, matrixId: u32)
    {
        if !sizeId
        {
            for index in 16'u32 do
                .lists[0, matrixId, index] = DefaultScalingList4x4[index]
            return
        }

        for index in 64'u32 do
            .lists[sizeId, matrixId, index] = matrixId < 3 ? DefaultScalingListIntra[index] : DefaultScalingListInter[index]
        if sizeId > 1 do
            .dc[sizeId - 2, matrixId] = 16
    }
}

// One sequence parameter set, clause 7.3.2.2.1, with the variables clause 7.4.3.2.1 derives.
struct Sps
{
    valid: bool

    chromaFormatIdc:  u32
    separateColour:   bool
    width:            u32     // pic_width_in_luma_samples.
    height:           u32     // pic_height_in_luma_samples.
    cropLeft:         u32
    cropRight:        u32
    cropTop:          u32
    cropBottom:       u32
    bitDepthLuma:     u32
    bitDepthChroma:   u32
    log2MaxPocLsb:    u32
    maxDecPicBuffering: u32
    maxNumReorder:    u32

    minCbLog2Size:    u32     // MinCbLog2SizeY.
    ctbLog2Size:      u32     // CtbLog2SizeY.
    minTbLog2Size:    u32     // MinTbLog2SizeY.
    maxTbLog2Size:    u32     // MaxTbLog2SizeY.
    maxTrafoDepthInter: u32
    maxTrafoDepthIntra: u32

    scalingListEnabled:   bool
    ampEnabled:           bool
    saoEnabled:           bool
    pcmEnabled:           bool
    pcmBitDepthLuma:      u32
    pcmBitDepthChroma:    u32
    pcmLog2MinSize:       u32
    pcmLog2MaxSize:       u32
    pcmLoopFilterDisabled: bool

    numShortTermRps:  u32
    shortTermRps:     [65] ShortTermRps

    longTermRefPics:      bool
    numLongTermRefPicsSps: u32
    ltPocLsbSps:          [32] u32
    ltUsedByCurrSps:      [32] bool

    temporalMvpEnabled:   bool
    strongIntraSmoothing: bool

    // Clause 7.4.3.2.2: the range extensions, which Main 10 leaves off.
    transformSkipRotation:   bool
    transformSkipContext:    bool
    implicitRdpcm:           bool
    explicitRdpcm:           bool
    extendedPrecision:       bool
    intraSmoothingDisabled:  bool
    highPrecisionOffsets:    bool
    persistentRiceAdaptation: bool
    cabacBypassAlignment:    bool

    scalingLists: ScalingLists

    // Derived geometry.
    ctbSize:          u32
    minCbSize:        u32
    widthInCtbs:      u32
    heightInCtbs:     u32
    sizeInCtbs:       u32
    widthInMinCbs:    u32
    heightInMinCbs:   u32
    widthInMinTbs:    u32
    heightInMinTbs:   u32
    qpBdOffsetY:      s32
    qpBdOffsetC:      s32
    subWidthC:        u32
    subHeightC:       u32
    chromaArrayType:  u32
}

impl Sps
{
    // Returns the visible picture size after the conformance window is applied.
    mtd const visibleWidth()->u32 => .width - (.cropLeft + .cropRight) * .subWidthC
    mtd const visibleHeight()->u32 => .height - (.cropTop + .cropBottom) * .subHeightC

    // Reads one sequence parameter set, clause 7.3.2.2.1.
    mtd read(reader: *BitReader) fail
    {
        discard reader.read(4)
        let maxSubLayersMinus1 = reader.read(3)
        discard reader.bit()
        try readProfileTierLevel(reader, maxSubLayersMinus1)

        discard reader.ue()
        .chromaFormatIdc = reader.ue()
        if .chromaFormatIdc == 3 do
            .separateColour = reader.bit() != 0
        if .chromaFormatIdc != 1 do
            fail UnsupportedFormatError{"HEVC decoder reads 4:2:0 chroma only"}

        .subWidthC       = 2
        .subHeightC      = 2
        .chromaArrayType = .separateColour ? 0 : .chromaFormatIdc

        .width  = reader.ue()
        .height = reader.ue()
        if reader.bit()
        {
            .cropLeft   = reader.ue()
            .cropRight  = reader.ue()
            .cropTop    = reader.ue()
            .cropBottom = reader.ue()
        }

        .bitDepthLuma   = reader.ue() + 8
        .bitDepthChroma = reader.ue() + 8
        if .bitDepthLuma > 10 or .bitDepthChroma > 10 or .bitDepthLuma != .bitDepthChroma do
            fail UnsupportedFormatError{"HEVC decoder reads 8-bit and 10-bit streams only"}

        .log2MaxPocLsb = reader.ue() + 4
        if .log2MaxPocLsb > 16 do
            fail InvalidFormatError{"HEVC picture order count range is out of bounds"}

        let subLayerOrdering = reader.bit() != 0
        for index in (subLayerOrdering ? 0'u32 : maxSubLayersMinus1) to maxSubLayersMinus1
        {
            .maxDecPicBuffering = reader.ue() + 1
            .maxNumReorder      = reader.ue()
            discard reader.ue()
        }

        .minCbLog2Size      = reader.ue() + 3
        .ctbLog2Size        = .minCbLog2Size + reader.ue()
        .minTbLog2Size      = reader.ue() + 2
        .maxTbLog2Size      = .minTbLog2Size + reader.ue()
        .maxTrafoDepthInter = reader.ue()
        .maxTrafoDepthIntra = reader.ue()
        if .ctbLog2Size > MaxCtbLog2SizeY or .minCbLog2Size < MinCbLog2SizeAllowed or .minCbLog2Size > .ctbLog2Size do
            fail InvalidFormatError{"HEVC coding block sizes are out of range"}
        if .maxTbLog2Size > 5 or .minTbLog2Size < 2 or .minTbLog2Size > .maxTbLog2Size do
            fail InvalidFormatError{"HEVC transform block sizes are out of range"}

        .scalingListEnabled = reader.bit() != 0
        .scalingLists.setFlat()
        if .scalingListEnabled
        {
            .scalingLists.setDefaults()
            if reader.bit() do
                try .scalingLists.read(reader)
        }

        .ampEnabled = reader.bit() != 0
        .saoEnabled = reader.bit() != 0
        .pcmEnabled = reader.bit() != 0
        if .pcmEnabled
        {
            .pcmBitDepthLuma       = reader.read(4) + 1
            .pcmBitDepthChroma     = reader.read(4) + 1
            .pcmLog2MinSize        = reader.ue() + 3
            .pcmLog2MaxSize        = .pcmLog2MinSize + reader.ue()
            .pcmLoopFilterDisabled = reader.bit() != 0
            fail UnsupportedFormatError{"HEVC pulse code modulation blocks are not supported"}
        }

        .numShortTermRps = reader.ue()
        if .numShortTermRps > 64 do
            fail InvalidFormatError{"HEVC sequence declares too many short-term reference picture sets"}
        for index in .numShortTermRps do
            try readShortTermRps(reader, &.shortTermRps[0], index, .numShortTermRps)

        .longTermRefPics = reader.bit() != 0
        if .longTermRefPics
        {
            .numLongTermRefPicsSps = reader.ue()
            if .numLongTermRefPicsSps > 32 do
                fail InvalidFormatError{"HEVC sequence declares too many long-term reference pictures"}
            for index in .numLongTermRefPicsSps
            {
                .ltPocLsbSps[index]     = reader.read(.log2MaxPocLsb)
                .ltUsedByCurrSps[index] = reader.bit() != 0
            }
        }

        .temporalMvpEnabled   = reader.bit() != 0
        .strongIntraSmoothing = reader.bit() != 0

        // The video usability information carries no decoding parameter this decoder needs, and
        // the range extensions follow it, so it is parsed only far enough to skip it.
        if reader.bit() do
            try skipVuiParameters(reader, maxSubLayersMinus1)

        if reader.bit()
        {
            let rangeExtension = reader.bit() != 0
            let multilayer     = reader.bit() != 0
            let extension3d    = reader.bit() != 0
            let screenContent  = reader.bit() != 0
            discard reader.read(4)
            if rangeExtension
            {
                .transformSkipRotation    = reader.bit() != 0
                .transformSkipContext     = reader.bit() != 0
                .implicitRdpcm            = reader.bit() != 0
                .explicitRdpcm            = reader.bit() != 0
                .extendedPrecision        = reader.bit() != 0
                .intraSmoothingDisabled   = reader.bit() != 0
                .highPrecisionOffsets     = reader.bit() != 0
                .persistentRiceAdaptation = reader.bit() != 0
                .cabacBypassAlignment     = reader.bit() != 0
            }

            if multilayer or extension3d or screenContent do
                fail UnsupportedFormatError{"HEVC multilayer, 3D and screen content extensions are not supported"}
            if .extendedPrecision or .explicitRdpcm or .persistentRiceAdaptation or .cabacBypassAlignment do
                fail UnsupportedFormatError{"HEVC range extension tools are not supported"}
        }

        if reader.overran do
            fail InvalidFormatError{"HEVC sequence parameter set is truncated"}

        .derive()
        try .validate()
        .valid = true
    }

    // Computes the geometry clause 7.4.3.2.1 derives from the coded sizes.
    private mtd derive()
    {
        .ctbSize        = 1'u32 << .ctbLog2Size
        .minCbSize      = 1'u32 << .minCbLog2Size
        .widthInCtbs    = (.width + .ctbSize - 1) / .ctbSize
        .heightInCtbs   = (.height + .ctbSize - 1) / .ctbSize
        .sizeInCtbs     = .widthInCtbs * .heightInCtbs
        .widthInMinCbs  = .width / .minCbSize
        .heightInMinCbs = .height / .minCbSize
        .widthInMinTbs  = .width >> .minTbLog2Size
        .heightInMinTbs = .height >> .minTbLog2Size
        .qpBdOffsetY    = cast(s32) (.bitDepthLuma - 8) * 6
        .qpBdOffsetC    = cast(s32) (.bitDepthChroma - 8) * 6
    }

    // Rejects a sequence this decoder cannot reconstruct.
    private mtd const validate() fail
    {
        if !.width or !.height do
            fail InvalidFormatError{"HEVC sequence declares an empty picture"}
        if .width % .minCbSize or .height % .minCbSize do
            fail InvalidFormatError{"HEVC picture size is not a multiple of the minimum coding block"}
        if .width > 16384 or .height > 16384 do
            fail UnsupportedFormatError{"HEVC picture exceeds the supported size"}
        if .maxDecPicBuffering > 16 do
            fail InvalidFormatError{"HEVC decoded picture buffer exceeds sixteen pictures"}
        if .visibleWidth() == 0 or .visibleHeight() == 0 do
            fail InvalidFormatError{"HEVC conformance window leaves no visible picture"}
    }
}

// One picture parameter set, clause 7.3.2.3.1.
struct Pps
{
    valid: bool

    spsId:                     u32
    dependentSliceSegments:    bool
    outputFlagPresent:         bool
    numExtraSliceHeaderBits:   u32
    signDataHiding:            bool
    cabacInitPresent:          bool
    numRefIdxL0Default:        u32
    numRefIdxL1Default:        u32
    initQp:                    s32
    constrainedIntraPred:      bool
    transformSkipEnabled:      bool
    cuQpDeltaEnabled:          bool
    diffCuQpDeltaDepth:        u32
    cbQpOffset:                s32
    crQpOffset:                s32
    sliceChromaQpOffsetsPresent: bool
    weightedPred:              bool
    weightedBipred:            bool
    transquantBypassEnabled:   bool
    tilesEnabled:              bool
    entropyCodingSync:         bool
    numTileColumns:            u32 = 1
    numTileRows:               u32 = 1
    uniformSpacing:            bool = true
    columnWidth:               [32] u32
    rowHeight:                 [32] u32
    loopFilterAcrossTiles:     bool = true
    loopFilterAcrossSlices:    bool
    deblockingControlPresent:  bool
    deblockingOverrideEnabled: bool
    deblockingDisabled:        bool
    betaOffsetDiv2:            s32
    tcOffsetDiv2:              s32
    scalingListDataPresent:    bool
    listsModificationPresent:  bool
    log2ParallelMergeLevel:    u32
    sliceHeaderExtension:      bool

    // Clause 7.3.2.3.2: the range extensions.
    log2MaxTransformSkipSize:  u32 = 2
    crossComponentPrediction:  bool
    chromaQpOffsetListEnabled: bool
    diffCuChromaQpOffsetDepth: u32
    chromaQpOffsetListLen:     u32
    cbQpOffsetList:            [6] s32
    crQpOffsetList:            [6] s32
    log2SaoOffsetScaleLuma:    u32
    log2SaoOffsetScaleChroma:  u32

    scalingLists: ScalingLists

    // Derived tile geometry, clause 6.5.1.
    colBoundary: [33] u32
    rowBoundary: [33] u32
}

impl Pps
{
    // Reads one picture parameter set, clause 7.3.2.3.1.
    //
    // `sps` is the sequence this set refers to, which the caller resolved from the identifier the
    // set carries: the tile geometry cannot be derived without it.
    mtd read(reader: *BitReader, sps: const *Sps) fail
    {
        .spsId                    = reader.ue()
        .dependentSliceSegments   = reader.bit() != 0
        .outputFlagPresent        = reader.bit() != 0
        .numExtraSliceHeaderBits  = reader.read(3)
        .signDataHiding           = reader.bit() != 0
        .cabacInitPresent         = reader.bit() != 0
        .numRefIdxL0Default       = reader.ue() + 1
        .numRefIdxL1Default       = reader.ue() + 1
        .initQp                   = reader.se() + 26
        .constrainedIntraPred     = reader.bit() != 0
        .transformSkipEnabled     = reader.bit() != 0
        .cuQpDeltaEnabled         = reader.bit() != 0
        if .cuQpDeltaEnabled do
            .diffCuQpDeltaDepth = reader.ue()
        .cbQpOffset                  = reader.se()
        .crQpOffset                  = reader.se()
        .sliceChromaQpOffsetsPresent = reader.bit() != 0
        .weightedPred                = reader.bit() != 0
        .weightedBipred              = reader.bit() != 0
        .transquantBypassEnabled     = reader.bit() != 0
        .tilesEnabled                = reader.bit() != 0
        .entropyCodingSync           = reader.bit() != 0
        if .tilesEnabled
        {
            .numTileColumns = reader.ue() + 1
            .numTileRows    = reader.ue() + 1
            if .numTileColumns > 32 or .numTileRows > 32 do
                fail UnsupportedFormatError{"HEVC picture declares more than thirty-two tile rows or columns"}
            .uniformSpacing = reader.bit() != 0
            if !.uniformSpacing
            {
                for index in .numTileColumns - 1 do
                    .columnWidth[index] = reader.ue() + 1
                for index in .numTileRows - 1 do
                    .rowHeight[index] = reader.ue() + 1
            }

            .loopFilterAcrossTiles = reader.bit() != 0
        }

        .loopFilterAcrossSlices   = reader.bit() != 0
        .deblockingControlPresent = reader.bit() != 0
        if .deblockingControlPresent
        {
            .deblockingOverrideEnabled = reader.bit() != 0
            .deblockingDisabled        = reader.bit() != 0
            if !.deblockingDisabled
            {
                .betaOffsetDiv2 = reader.se()
                .tcOffsetDiv2   = reader.se()
            }
        }

        .scalingListDataPresent = reader.bit() != 0
        .scalingLists           = sps.scalingLists
        if .scalingListDataPresent do
            try .scalingLists.read(reader)

        .listsModificationPresent = reader.bit() != 0
        .log2ParallelMergeLevel   = reader.ue() + 2
        .sliceHeaderExtension     = reader.bit() != 0

        if reader.bit()
        {
            let rangeExtension = reader.bit() != 0
            let multilayer     = reader.bit() != 0
            let extension3d    = reader.bit() != 0
            let screenContent  = reader.bit() != 0
            discard reader.read(4)
            if rangeExtension
            {
                if .transformSkipEnabled do
                    .log2MaxTransformSkipSize = reader.ue() + 2
                .crossComponentPrediction  = reader.bit() != 0
                .chromaQpOffsetListEnabled = reader.bit() != 0
                if .chromaQpOffsetListEnabled
                {
                    .diffCuChromaQpOffsetDepth = reader.ue()
                    .chromaQpOffsetListLen     = reader.ue() + 1
                    if .chromaQpOffsetListLen > 6 do
                        fail InvalidFormatError{"HEVC chroma quantization offset list is too long"}
                    for index in .chromaQpOffsetListLen
                    {
                        .cbQpOffsetList[index] = reader.se()
                        .crQpOffsetList[index] = reader.se()
                    }
                }

                .log2SaoOffsetScaleLuma   = reader.ue()
                .log2SaoOffsetScaleChroma = reader.ue()
            }

            if multilayer or extension3d or screenContent do
                fail UnsupportedFormatError{"HEVC multilayer, 3D and screen content extensions are not supported"}
            if .crossComponentPrediction or .chromaQpOffsetListEnabled do
                fail UnsupportedFormatError{"HEVC cross-component prediction and per-unit chroma offsets are not supported"}
        }

        if reader.overran do
            fail InvalidFormatError{"HEVC picture parameter set is truncated"}
        if .initQp < -sps.qpBdOffsetY or .initQp > 51 do
            fail InvalidFormatError{"HEVC initial quantization parameter is out of range"}

        .deriveTiles(sps)
        .valid = true
    }

    // Computes the tile column and row boundaries of clause 6.5.1, in coding tree blocks.
    private mtd deriveTiles(sps: const *Sps)
    {
        if .uniformSpacing
        {
            for index in .numTileColumns + 1 do
                .colBoundary[index] = index * sps.widthInCtbs / .numTileColumns
            for index in .numTileRows + 1 do
                .rowBoundary[index] = index * sps.heightInCtbs / .numTileRows
            return
        }

        .colBoundary[0] = 0
        for index in .numTileColumns - 1 do
            .colBoundary[index + 1] = .colBoundary[index] + .columnWidth[index]
        .colBoundary[.numTileColumns] = sps.widthInCtbs

        .rowBoundary[0] = 0
        for index in .numTileRows - 1 do
            .rowBoundary[index + 1] = .rowBoundary[index] + .rowHeight[index]
        .rowBoundary[.numTileRows] = sps.heightInCtbs
    }

    // Returns the tile a coding tree block belongs to, or zero when the picture is one tile.
    mtd const tileOf(ctbX, ctbY: u32)->u32
    {
        if !.tilesEnabled do
            return 0
        var column = 0'u32
        while column + 1 < .numTileColumns and ctbX >= .colBoundary[column + 1] do
            column += 1
        var row = 0'u32
        while row + 1 < .numTileRows and ctbY >= .rowBoundary[row + 1] do
            row += 1
        return row * .numTileColumns + column
    }
}

// Reads and discards one `profile_tier_level` structure, clause 7.3.3.
//
// Nothing below the level identifier changes how a conforming stream decodes, and the structure
// has a fixed length whatever the profile, so it is skipped rather than interpreted.
func readProfileTierLevel(reader: *BitReader, maxSubLayersMinus1: u32) fail
{
    // The profile, tier and constraint flags take eighty-eight bits whatever the profile, and the
    // level identifier eight more.
    discard reader.read(32)
    discard reader.read(32)
    discard reader.read(24)
    discard reader.read(8)

    var profilePresent, levelPresent: [8] bool
    for index in maxSubLayersMinus1
    {
        profilePresent[index] = reader.bit() != 0
        levelPresent[index]   = reader.bit() != 0
    }

    if maxSubLayersMinus1 > 0
    {
        for index in maxSubLayersMinus1 until 8'u32 do
            discard reader.read(2)
    }

    for index in maxSubLayersMinus1
    {
        if profilePresent[index]
        {
            discard reader.read(32)
            discard reader.read(32)
            discard reader.read(24)
        }

        if levelPresent[index] do
            discard reader.read(8)
    }

    if reader.overran do
        fail InvalidFormatError{"HEVC profile, tier and level structure is truncated"}
}

// Reads one short-term reference picture set into `sets[index]`, clause 7.3.7.
//
// A set may state its pictures directly, or predict them from an earlier set by shifting every
// delta by one picture order count difference; the prediction is resolved here so nothing
// downstream has to know which spelling the stream used.
func readShortTermRps(reader: *BitReader, sets: [*] ShortTermRps, index, count: u32) fail
{
    var target: ShortTermRps

    var interPrediction = false
    if index != 0 do
        interPrediction = reader.bit() != 0

    if !interPrediction
    {
        let negative = reader.ue()
        let positive = reader.ue()
        if negative > MaxRefPics or positive > MaxRefPics or negative + positive > MaxRefPics do
            fail InvalidFormatError{"HEVC reference picture set holds too many pictures"}

        target.negativeCount = negative
        target.positiveCount = positive

        var previous = 0's32
        for entry in negative
        {
            previous                     -= cast(s32) (reader.ue() + 1)
            target.negativeDelta[entry]  = previous
            target.negativeUsed[entry]   = reader.bit() != 0
        }

        previous = 0
        for entry in positive
        {
            previous                    += cast(s32) (reader.ue() + 1)
            target.positiveDelta[entry] = previous
            target.positiveUsed[entry]  = reader.bit() != 0
        }

        sets[index] = target
        if reader.overran do
            fail InvalidFormatError{"HEVC reference picture set is truncated"}
        return
    }

    var deltaIdx = 1'u32
    if index == count do
        deltaIdx = reader.ue() + 1
    if deltaIdx > index do
        fail InvalidFormatError{"HEVC reference picture set predicts from a set that does not precede it"}

    let sign      = reader.bit()
    let absDelta  = cast(s32) (reader.ue() + 1)
    let deltaRps  = sign ? -absDelta : absDelta
    let source    = &sets[index - deltaIdx]
    let sourceTotal = source.totalCount()

    var used, useDelta: [MaxRefPics + 1] bool
    for entry in sourceTotal + 1
    {
        used[entry] = reader.bit() != 0
        useDelta[entry] = true
        if !used[entry] do
            useDelta[entry] = reader.bit() != 0
    }

    // Clause 7.4.8, equation 7-61: the pictures of the source set, shifted by `deltaRps`, keep
    // their order once split back into the two halves by sign.
    var negativeCount = 0'u32
    for entry in source.positiveCount
    {
        let index2 = source.positiveCount - 1 - entry
        let delta  = source.positiveDelta[index2] + deltaRps
        if delta < 0 and useDelta[source.negativeCount + index2]
        {
            target.negativeDelta[negativeCount] = delta
            target.negativeUsed[negativeCount]  = used[source.negativeCount + index2]
            negativeCount += 1
        }
    }

    if deltaRps < 0 and useDelta[sourceTotal]
    {
        target.negativeDelta[negativeCount] = deltaRps
        target.negativeUsed[negativeCount]  = used[sourceTotal]
        negativeCount += 1
    }

    for entry in source.negativeCount
    {
        let delta = source.negativeDelta[entry] + deltaRps
        if delta < 0 and useDelta[entry]
        {
            target.negativeDelta[negativeCount] = delta
            target.negativeUsed[negativeCount]  = used[entry]
            negativeCount += 1
        }
    }

    var positiveCount = 0'u32
    for entry in source.negativeCount
    {
        let index2 = source.negativeCount - 1 - entry
        let delta  = source.negativeDelta[index2] + deltaRps
        if delta > 0 and useDelta[index2]
        {
            target.positiveDelta[positiveCount] = delta
            target.positiveUsed[positiveCount]  = used[index2]
            positiveCount += 1
        }
    }

    if deltaRps > 0 and useDelta[sourceTotal]
    {
        target.positiveDelta[positiveCount] = deltaRps
        target.positiveUsed[positiveCount]  = used[sourceTotal]
        positiveCount += 1
    }

    for entry in source.positiveCount
    {
        let delta = source.positiveDelta[entry] + deltaRps
        if delta > 0 and useDelta[source.negativeCount + entry]
        {
            target.positiveDelta[positiveCount] = delta
            target.positiveUsed[positiveCount]  = used[source.negativeCount + entry]
            positiveCount += 1
        }
    }

    if negativeCount > MaxRefPics or positiveCount > MaxRefPics do
        fail InvalidFormatError{"HEVC predicted reference picture set holds too many pictures"}

    target.negativeCount = negativeCount
    target.positiveCount = positiveCount
    sets[index] = target

    if reader.overran do
        fail InvalidFormatError{"HEVC reference picture set is truncated"}
}

// Reads and discards one `vui_parameters` structure, clause E.2.1.
//
// The video usability information describes how a picture should be shown, never how it decodes,
// so it is only walked far enough to reach the syntax that follows it.
func skipVuiParameters(reader: *BitReader, maxSubLayersMinus1: u32) fail
{
    if reader.bit()
    {
        let aspectRatioIdc = reader.read(8)
        if aspectRatioIdc == 255
        {
            discard reader.read(16)
            discard reader.read(16)
        }
    }

    if reader.bit() do
        discard reader.bit()
    if reader.bit()
    {
        discard reader.read(3)
        discard reader.bit()
        if reader.bit()
        {
            discard reader.read(8)
            discard reader.read(8)
            discard reader.read(8)
        }
    }

    if reader.bit()
    {
        discard reader.ue()
        discard reader.ue()
    }

    discard reader.bit()
    discard reader.bit()
    discard reader.bit()
    if reader.bit()
    {
        discard reader.ue()
        discard reader.ue()
        discard reader.ue()
        discard reader.ue()
    }

    if reader.bit()
    {
        discard reader.read(32)
        discard reader.read(32)
        if reader.bit() do
            discard reader.ue()
        if reader.bit() do
            try skipHrdParameters(reader, maxSubLayersMinus1)
    }

    if reader.bit()
    {
        discard reader.bit()
        discard reader.bit()
        discard reader.bit()
        discard reader.ue()
        discard reader.ue()
        discard reader.ue()
        discard reader.ue()
        discard reader.ue()
    }

    if reader.overran do
        fail InvalidFormatError{"HEVC video usability information is truncated"}
}

// Reads and discards one `hrd_parameters` structure, clause E.2.2.
func skipHrdParameters(reader: *BitReader, maxSubLayersMinus1: u32) fail
{
    var nalHrd, vclHrd, subPicParams = false
    nalHrd = reader.bit() != 0
    vclHrd = reader.bit() != 0
    if nalHrd or vclHrd
    {
        subPicParams = reader.bit() != 0
        if subPicParams
        {
            discard reader.read(8)
            discard reader.read(5)
            discard reader.bit()
            discard reader.read(5)
        }

        discard reader.read(4)
        discard reader.read(4)
        if subPicParams do
            discard reader.read(4)
        discard reader.read(5)
        discard reader.read(5)
        discard reader.read(5)
    }

    for layer in maxSubLayersMinus1 + 1
    {
        let fixedRateGeneral = reader.bit() != 0
        var fixedRateWithin  = fixedRateGeneral
        if !fixedRateGeneral do
            fixedRateWithin = reader.bit() != 0

        var lowDelay = false
        var cpbCount = 1'u32
        if fixedRateWithin do
            discard reader.ue()
        else do
            lowDelay = reader.bit() != 0
        if !lowDelay do
            cpbCount = reader.ue() + 1
        if cpbCount > 32 do
            fail InvalidFormatError{"HEVC hypothetical reference decoder declares too many buffers"}

        for pass in 2'u32
        {
            if (pass == 0 and !nalHrd) or (pass == 1 and !vclHrd) do
                continue
            for index in cpbCount
            {
                discard reader.ue()
                discard reader.ue()
                if subPicParams
                {
                    discard reader.ue()
                    discard reader.ue()
                }

                discard reader.bit()
            }
        }
    }

    if reader.overran do
        fail InvalidFormatError{"HEVC hypothetical reference decoder parameters are truncated"}
}
