//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns slice segment headers, reference picture sets, and prediction weights.
//
#global namespace Hevc
#global internal

using Core, Core.Errors

// Derives the signaled chroma offset, equations 7-57 and 7-58.
//
// The syntax always states this offset around the eight-bit midpoint. Sample prediction scales
// the result to the stream bit depth later; using the Main 10 midpoint here would scale it twice.
func deriveChromaOffset(deltaOffset, weight: s32, denominator: u32)->s32
{
    const Midpoint = 128's32
    let predicted = Midpoint - ((Midpoint * weight) >> denominator)
    return Math.clamp(deltaOffset + predicted, -Midpoint, Midpoint - 1)
}

// Network abstraction layer unit types, Table 7-1. Only the ones this decoder acts on are named.
const NalTrailN            = 0'u32
const NalRaslR             = 9'u32
const NalBlaWLp            = 16'u32
const NalIdrWRadl          = 19'u32
const NalIdrNLp            = 20'u32
const NalCraNut            = 21'u32
const NalReservedIrapVcl23 = 23'u32
const NalVps               = 32'u32
const NalSps               = 33'u32
const NalPps               = 34'u32
const NalAud               = 35'u32
const NalEos               = 36'u32
const NalEob               = 37'u32
const NalFillerData        = 38'u32
const NalPrefixSei         = 39'u32
const NalSuffixSei         = 40'u32

// Slice types, clause 7.4.7.1.
const SliceTypeB = 0'u32
const SliceTypeP = 1'u32
const SliceTypeI = 2'u32

// The two prediction lists a slice may use.
const ListCount = 2'u32

// Reports whether a unit type carries coded picture data.
func isVideoCodingNal(nalType: u32)->bool => nalType <= NalReservedIrapVcl23

// Reports whether a unit type starts an intra random access point picture, clause 3.73.
func isIrapNal(nalType: u32)->bool => nalType >= NalBlaWLp and nalType <= NalReservedIrapVcl23

// Reports whether a unit type starts an instantaneous decoding refresh picture.
func isIdrNal(nalType: u32)->bool => nalType == NalIdrWRadl or nalType == NalIdrNLp

// Reports whether a unit type carries a picture that is skipped after a random access point.
func isRaslNal(nalType: u32)->bool => nalType == 8 or nalType == NalRaslR

// Reports whether a unit type marks its picture as a reference for later pictures.
//
// The sub-layer non-reference types are the even ones below sixteen, clause 7.4.2.2.
func isReferenceNal(nalType: u32)->bool => nalType >= NalBlaWLp or (nalType & 1) != 0

// The explicit weights and offsets one reference picture uses, clause 7.3.6.3.
struct PredWeight
{
    lumaWeight:   s32 = 1
    lumaOffset:   s32
    chromaWeight: [2] s32
    chromaOffset: [2] s32
    lumaFlag:     bool
    chromaFlag:   bool
}

// One slice segment header, clause 7.3.6.1.
//
// A dependent slice segment carries only its address and entry points; everything else it takes
// from the independent segment before it, which is why the whole structure is copied forward
// rather than re-parsed.
struct SliceHeader
{
    firstSliceInPic:     bool
    noOutputOfPriorPics: bool
    ppsId:               u32
    dependent:           bool
    segmentAddress:      u32

    sliceType:           u32  = SliceTypeI
    picOutputFlag:       bool = true
    pocLsb:              u32
    shortTermRpsSpsFlag: bool
    shortTermRpsIdx:     u32
    localRps:            ShortTermRps
    usesLocalRps:        bool

    numLongTermSps:  u32
    numLongTermPics: u32
    ltPocLsb:        [32] u32
    ltUsedByCurr:    [32] bool
    ltMsbPresent:    [32] bool
    ltMsbCycle:      [32] u32

    temporalMvpEnabled: bool
    saoLuma:            bool
    saoChroma:          bool

    numRefIdx:        [ListCount] u32
    listModification: [ListCount] bool
    listEntry:        [ListCount, MaxRefPics] u32
    mvdL1Zero:        bool
    cabacInitFlag:    bool
    collocatedFromL0: bool = true
    collocatedRefIdx: u32
    maxNumMergeCand:  u32  = 5

    lumaLog2WeightDenom:   u32
    chromaLog2WeightDenom: u32
    weights:               [ListCount, MaxRefPics] PredWeight
    hasWeights:            bool

    sliceQpDelta:            s32
    sliceQp:                 s32
    cbQpOffset:              s32
    crQpOffset:              s32
    cuChromaQpOffsetEnabled: bool

    deblockingOverride:     bool
    deblockingDisabled:     bool
    betaOffsetDiv2:         s32
    tcOffsetDiv2:           s32
    loopFilterAcrossSlices: bool

    numEntryPointOffsets: u32
    entryPointOffsets:    Array'u32

    // Filled by the decoder once the header is parsed.
    nalType:      u32
    temporalId:   u32
    initType:     u32
    sliceAddress: u32     // Address in coding tree blocks, in the tile scan.
    sliceIndex:   u32     // Position of this slice among the picture's slices.
}

impl SliceHeader
{
    // Returns the reference picture set this slice uses.
    mtd const activeRps(sps: const *Sps)->const *ShortTermRps
    {
        if .usesLocalRps do
            return &.localRps
        return &sps.shortTermRps[.shortTermRpsIdx]
    }

    // Reads one slice segment header, clause 7.3.6.1.
    //
    // `previous` is the independent slice segment header this picture is already using, which a
    // dependent segment inherits everything but its own address from.
    mtd read(reader: *BitReader, sps: const *Sps, pps: const *Pps, nalType: u32, previous: const *SliceHeader) fail
    {
        .firstSliceInPic = reader.bit() != 0
        if isIrapNal(nalType) do
            .noOutputOfPriorPics = reader.bit() != 0
        .ppsId = reader.ue()

        if !.firstSliceInPic
        {
            if pps.dependentSliceSegments do
                .dependent = reader.bit() != 0

            // The address is as wide as the picture's coding tree block count needs.
            var bits = 0'u32
            while (1'u32 << bits) < sps.sizeInCtbs do
                bits += 1
            .segmentAddress = reader.read(bits)
            if .segmentAddress >= sps.sizeInCtbs do
                fail InvalidFormatError{"HEVC slice segment address is past the end of the picture"}
        }

        if .dependent
        {
            if !previous.firstSliceInPic and previous.segmentAddress == 0 and !previous.dependent do
                fail InvalidFormatError{"HEVC dependent slice segment has no independent segment before it"}
            .inheritFrom(previous)
            try .readEntryPoints(reader, pps)
            return
        }

        for pps.numExtraSliceHeaderBits do
            discard reader.bit()

        .sliceType = reader.ue()
        if .sliceType > SliceTypeI do
            fail InvalidFormatError{"HEVC slice declares an unknown slice type"}
        if pps.outputFlagPresent do
            .picOutputFlag = reader.bit() != 0
        if sps.separateColour do
            discard reader.read(2)

        if !isIdrNal(nalType)
        {
            .pocLsb              = reader.read(sps.log2MaxPocLsb)
            .shortTermRpsSpsFlag = reader.bit() != 0
            if !.shortTermRpsSpsFlag
            {
                // A set stated in the header takes the slot past the ones the sequence declared.
                var sets: [65] ShortTermRps
                for index in sps.numShortTermRps do
                    sets[index] = sps.shortTermRps[index]
                try readShortTermRps(reader, &sets[0], sps.numShortTermRps, sps.numShortTermRps)
                .localRps     = sets[sps.numShortTermRps]
                .usesLocalRps = true
            }
            elif sps.numShortTermRps > 1
            {
                var bits = 0'u32
                while (1'u32 << bits) < sps.numShortTermRps do
                    bits += 1
                .shortTermRpsIdx = reader.read(bits)
                if .shortTermRpsIdx >= sps.numShortTermRps do
                    fail InvalidFormatError{"HEVC slice selects a reference picture set the sequence does not declare"}
            }

            if sps.longTermRefPics
            {
                if sps.numLongTermRefPicsSps > 0 do
                    .numLongTermSps = reader.ue()
                .numLongTermPics = reader.ue()
                if .numLongTermSps > sps.numLongTermRefPicsSps or .numLongTermSps + .numLongTermPics > 32 do
                    fail InvalidFormatError{"HEVC slice declares too many long-term reference pictures"}

                var previousMsbCycle = 0'u32
                for index in .numLongTermSps + .numLongTermPics
                {
                    if index < .numLongTermSps
                    {
                        var entry = 0'u32
                        if sps.numLongTermRefPicsSps > 1
                        {
                            var bits = 0'u32
                            while (1'u32 << bits) < sps.numLongTermRefPicsSps do
                                bits += 1
                            entry = reader.read(bits)
                        }

                        if entry >= sps.numLongTermRefPicsSps do
                            fail InvalidFormatError{"HEVC slice selects a long-term picture the sequence does not declare"}
                        .ltPocLsb[index]     = sps.ltPocLsbSps[entry]
                        .ltUsedByCurr[index] = sps.ltUsedByCurrSps[entry]
                    }
                    else
                    {
                        .ltPocLsb[index]     = reader.read(sps.log2MaxPocLsb)
                        .ltUsedByCurr[index] = reader.bit() != 0
                    }

                    .ltMsbPresent[index] = reader.bit() != 0
                    if .ltMsbPresent[index]
                    {
                        let cycle = reader.ue()

                        // Clause 7.4.7.1: the cycles of the long-term pictures past the first of
                        // each half are stated as differences.
                        .ltMsbCycle[index] = index == 0 or index == .numLongTermSps ? cycle : cycle + previousMsbCycle
                        previousMsbCycle   = .ltMsbCycle[index]
                    }
                }
            }

            if sps.temporalMvpEnabled do
                .temporalMvpEnabled = reader.bit() != 0
        }

        if sps.saoEnabled
        {
            .saoLuma = reader.bit() != 0
            if sps.chromaArrayType != 0 do
                .saoChroma = reader.bit() != 0
        }

        .numRefIdx[0] = pps.numRefIdxL0Default
        .numRefIdx[1] = pps.numRefIdxL1Default
        if .sliceType != SliceTypeI
        {
            if reader.bit()
            {
                .numRefIdx[0] = reader.ue() + 1
                if .sliceType == SliceTypeB do
                    .numRefIdx[1] = reader.ue() + 1
            }

            if .numRefIdx[0] > MaxRefPics or .numRefIdx[1] > MaxRefPics do
                fail InvalidFormatError{"HEVC slice activates too many reference pictures"}
            if .sliceType != SliceTypeB do
                .numRefIdx[1] = 0

            // The modification syntax needs the number of pictures the set makes available, which
            // only the caller's reference picture set knows.
            let totalCurr = .picTotalCurr(sps)
            if pps.listsModificationPresent and totalCurr > 1
            {
                var bits = 0'u32
                while (1'u32 << bits) < totalCurr do
                    bits += 1
                for list in (.sliceType == SliceTypeB ? 2'u32 : 1'u32)
                {
                    .listModification[list] = reader.bit() != 0
                    if !.listModification[list] do
                        continue
                    for index in .numRefIdx[list]
                    {
                        .listEntry[list, index] = reader.read(bits)
                        if .listEntry[list, index] >= totalCurr do
                            fail InvalidFormatError{"HEVC reference list modification selects a picture that is not available"}
                    }
                }
            }

            if .sliceType == SliceTypeB do
                .mvdL1Zero = reader.bit() != 0
            if pps.cabacInitPresent do
                .cabacInitFlag = reader.bit() != 0

            if .temporalMvpEnabled
            {
                if .sliceType == SliceTypeB do
                    .collocatedFromL0 = reader.bit() != 0
                let activeInList = .collocatedFromL0 ? .numRefIdx[0] : .numRefIdx[1]
                if activeInList > 1 do
                    .collocatedRefIdx = reader.ue()
                if .collocatedRefIdx >= activeInList do
                    fail InvalidFormatError{"HEVC collocated reference index is past the end of its list"}
            }

            if (pps.weightedPred and .sliceType == SliceTypeP) or (pps.weightedBipred and .sliceType == SliceTypeB) do
                try .readPredWeightTable(reader, sps)

            let fiveMinus = reader.ue()
            if fiveMinus > 4 do
                fail InvalidFormatError{"HEVC slice declares an unusable merge candidate count"}
            .maxNumMergeCand = 5 - fiveMinus
        }

        .sliceQpDelta = reader.se()
        .sliceQp      = pps.initQp + .sliceQpDelta
        if .sliceQp < -sps.qpBdOffsetY or .sliceQp > 51 do
            fail InvalidFormatError{"HEVC slice quantization parameter is out of range"}

        if pps.sliceChromaQpOffsetsPresent
        {
            .cbQpOffset = reader.se()
            .crQpOffset = reader.se()
        }

        if pps.chromaQpOffsetListEnabled do
            .cuChromaQpOffsetEnabled = reader.bit() != 0

        .deblockingDisabled = pps.deblockingDisabled
        .betaOffsetDiv2     = pps.betaOffsetDiv2
        .tcOffsetDiv2       = pps.tcOffsetDiv2
        if pps.deblockingOverrideEnabled do
            .deblockingOverride = reader.bit() != 0
        if .deblockingOverride
        {
            .deblockingDisabled = reader.bit() != 0
            if !.deblockingDisabled
            {
                .betaOffsetDiv2 = reader.se()
                .tcOffsetDiv2   = reader.se()
            }
        }

        .loopFilterAcrossSlices = pps.loopFilterAcrossSlices
        if pps.loopFilterAcrossSlices and (.saoLuma or .saoChroma or !.deblockingDisabled) do
            .loopFilterAcrossSlices = reader.bit() != 0

        try .readEntryPoints(reader, pps)
        if reader.overran do
            fail InvalidFormatError{"HEVC slice segment header is truncated"}
    }

    // Returns `NumPicTotalCurr`, the pictures this slice may predict from, clause 7.4.7.1.
    mtd const picTotalCurr(sps: const *Sps)->u32
    {
        var total = .activeRps(sps).usedCount()
        for index in .numLongTermSps + .numLongTermPics where .ltUsedByCurr[index] do
            total += 1
        return total
    }

    // Reads the entry point offsets and the header extension that follow every segment.
    private mtd readEntryPoints(reader: *BitReader, pps: const *Pps) fail
    {
        if pps.tilesEnabled or pps.entropyCodingSync
        {
            .numEntryPointOffsets = reader.ue()
            if .numEntryPointOffsets > 0
            {
                let offsetBits = reader.ue() + 1
                if offsetBits > 32 do
                    fail InvalidFormatError{"HEVC entry point offsets are too wide"}
                if .numEntryPointOffsets > 1 << 20 do
                    fail InvalidFormatError{"HEVC slice declares too many entry points"}
                .entryPointOffsets.clear()
                .entryPointOffsets.reserve(cast(u64) .numEntryPointOffsets)
                for index in .numEntryPointOffsets do
                    .entryPointOffsets.add(reader.read(offsetBits) + 1)
            }
        }

        if pps.sliceHeaderExtension
        {
            let length = reader.ue()
            for length do
                discard reader.read(8)
        }

        // The header ends on a byte boundary, clause 7.3.2.12.
        discard reader.bit()
        while reader.bitPos & 7 do
            discard reader.bit()

        if reader.overran do
            fail InvalidFormatError{"HEVC slice segment header is truncated"}
    }

    // Reads the explicit prediction weights, clause 7.3.6.3.
    //
    // The standard omits the flag of a reference picture that is the current picture itself,
    // which only screen content coding can produce; every picture here therefore carries one.
    private mtd readPredWeightTable(reader: *BitReader, sps: const *Sps) fail
    {
        .hasWeights            = true
        .lumaLog2WeightDenom   = reader.ue()
        .chromaLog2WeightDenom = .lumaLog2WeightDenom
        if .lumaLog2WeightDenom > 7 do
            fail InvalidFormatError{"HEVC luma weight denominator is out of range"}
        if sps.chromaArrayType != 0
        {
            let delta = reader.se() + cast(s32) .lumaLog2WeightDenom
            if delta < 0 or delta > 7 do
                fail InvalidFormatError{"HEVC chroma weight denominator is out of range"}
            .chromaLog2WeightDenom = cast(u32) delta
        }

        let lists = .sliceType == SliceTypeB ? 2'u32 : 1'u32
        for list in lists
        {
            for index in .numRefIdx[list] do
                .weights[list, index].lumaFlag = reader.bit() != 0
            if sps.chromaArrayType != 0
            {
                for index in .numRefIdx[list] do
                    .weights[list, index].chromaFlag = reader.bit() != 0
            }

            for index in .numRefIdx[list]
            {
                let weight = &.weights[list, index]
                weight.lumaWeight = 1 << .lumaLog2WeightDenom
                if weight.lumaFlag
                {
                    weight.lumaWeight = (1 << .lumaLog2WeightDenom) + reader.se()
                    weight.lumaOffset = reader.se()
                }

                for component in 2'u32
                {
                    weight.chromaWeight[component] = 1 << .chromaLog2WeightDenom
                    if !weight.chromaFlag do
                        continue

                    weight.chromaWeight[component] = (1 << .chromaLog2WeightDenom) + reader.se()

                    let deltaOffset = reader.se()
                    weight.chromaOffset[component] = deriveChromaOffset(deltaOffset, weight.chromaWeight[component], .chromaLog2WeightDenom)
                }
            }
        }

        if reader.overran do
            fail InvalidFormatError{"HEVC prediction weight table is truncated"}
    }

    // Takes everything a dependent slice segment inherits from the segment it continues.
    private mtd inheritFrom(previous: const *SliceHeader)
    {
        let address    = .segmentAddress
        let dependent  = .dependent
        let firstInPic = .firstSliceInPic
        let ppsId      = .ppsId
        let priorPics  = .noOutputOfPriorPics

        me[] = previous[]

        .segmentAddress       = address
        .dependent            = dependent
        .firstSliceInPic      = firstInPic
        .ppsId                = ppsId
        .noOutputOfPriorPics  = priorPics
        .numEntryPointOffsets = 0
        .entryPointOffsets.clear()
    }
}
