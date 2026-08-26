#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Walks one code through its decoding tree and returns the entry it reaches, or minus one.
func mpeg4WalkTree(tree: const [..] s16, length: u32, code: u32)->s32
{
    var node = 0's32
    for index in length
    {
        let bit  = (code >> (length - 1 - index)) & 1
        let slot = cast(u64) (node * 2) + cast(u64) bit
        if slot >= @countof(tree) do
            return -1

        let next = tree[slot]
        if !next do
            return -1
        if next < 0
        {
            // A leaf before the last bit would mean the code passes through another code.
            if index != length - 1 do
                return -1
            return cast(s32) (-next - 1)
        }

        node = cast(s32) next
    }

    return -1
}

// Requires the decoding tree of one table to hold exactly the codes the normative arrays state.
//
// The tables are written twice on purpose: `Len`/`Cod` is the standard's own form, and `Tree` is
// what the decoder walks. This is what keeps the second from drifting from the first.
func mpeg4AssertTable(name: string, lengths: const [..] u8, codes: const [..] u16, tree: const [..] s16)
{
    @assert(@countof(lengths) == @countof(codes))

    var kraft = 0.0'f64
    for entry in @countof(lengths)
    {
        let length = cast(u32) lengths[entry]
        @assert(length > 0 and length <= 24)
        @assert(cast(u32) codes[entry] < (1'u32 << length))
        kraft += Math.pow(0.5'f64, cast(f64) length)

        let reached = mpeg4WalkTree(tree, length, cast(u32) codes[entry])
        if reached != cast(s32) entry do
            @print("mpeg4 table ", name, ": entry ", entry, " decodes to ", reached, "\n")
        @assert(reached == cast(s32) entry)
    }

    // These codes are not complete: the format leaves bit patterns undefined, and a decoder that
    // meets one has met a corrupt stream. What must hold is that none of them overlaps.
    @assert(kraft <= 1.0'f64 + 1e-9)

    for slot in @countof(tree)
    {
        let value = tree[slot]
        if value > 0 do
            @assert(cast(u64) value * 2 + 1 < @countof(tree) and cast(u64) value * 2 > slot)
        elif value < 0 do
            @assert(cast(u64) (-value - 1) < @countof(lengths))
    }
}

// Every variable length code table of Annex B.
#test
{
    mpeg4AssertTable("mcbpc I", Mpeg4.McbpcILen, Mpeg4.McbpcICod, Mpeg4.McbpcITree)
    mpeg4AssertTable("mcbpc P", Mpeg4.McbpcPLen, Mpeg4.McbpcPCod, Mpeg4.McbpcPTree)
    mpeg4AssertTable("cbpy", Mpeg4.CbpyLen, Mpeg4.CbpyCod, Mpeg4.CbpyTree)
    mpeg4AssertTable("mvd", Mpeg4.MvdLen, Mpeg4.MvdCod, Mpeg4.MvdTree)
    mpeg4AssertTable("dc luma", Mpeg4.DcLumaLen, Mpeg4.DcLumaCod, Mpeg4.DcLumaTree)
    mpeg4AssertTable("dc chroma", Mpeg4.DcChromaLen, Mpeg4.DcChromaCod, Mpeg4.DcChromaTree)
    mpeg4AssertTable("tcoef intra", Mpeg4.TcoefIntraLen, Mpeg4.TcoefIntraCod, Mpeg4.TcoefIntraTree)
    mpeg4AssertTable("tcoef inter", Mpeg4.TcoefInterLen, Mpeg4.TcoefInterCod, Mpeg4.TcoefInterTree)
}

// The escape event shares the code space of both coefficient tables, so it must not be in either
// tree and its own code must not be a prefix of anything that is.
#test
{
    @assert(mpeg4WalkTree(Mpeg4.TcoefIntraTree, Mpeg4.TcoefEscapeLen, Mpeg4.TcoefEscapeCod) < 0)
    @assert(mpeg4WalkTree(Mpeg4.TcoefInterTree, Mpeg4.TcoefEscapeLen, Mpeg4.TcoefEscapeCod) < 0)

    for table in 2'u32
    {
        let lengths: const [..] u8  = table ? Mpeg4.TcoefInterLen : Mpeg4.TcoefIntraLen
        let codes:   const [..] u16 = table ? Mpeg4.TcoefInterCod : Mpeg4.TcoefIntraCod
        for entry in @countof(lengths)
        {
            let length = cast(u32) lengths[entry]
            if length < Mpeg4.TcoefEscapeLen do
                @assert((Mpeg4.TcoefEscapeCod >> (Mpeg4.TcoefEscapeLen - length)) != cast(u32) codes[entry])
            else do
                @assert((cast(u32) codes[entry] >> (length - Mpeg4.TcoefEscapeLen)) != Mpeg4.TcoefEscapeCod)
        }
    }
}

// Each coefficient table names 102 distinct events, and no two share a run, a level, and a last.
#test
{
    @assert(@countof(Mpeg4.TcoefIntraLen) == 102 and @countof(Mpeg4.TcoefInterLen) == 102)
    for table in 2'u32
    {
        let last:  const [..] u8  = table ? Mpeg4.TcoefInterLast : Mpeg4.TcoefIntraLast
        let run:   const [..] u8  = table ? Mpeg4.TcoefInterRun : Mpeg4.TcoefIntraRun
        let level: const [..] u16 = table ? Mpeg4.TcoefInterLevel : Mpeg4.TcoefIntraLevel
        for a in 102'u64
        {
            @assert(last[a] <= 1 and run[a] < 64 and level[a] > 0)
            for b in a + 1 until 102'u64 do
                @assert(last[a] != last[b] or run[a] != run[b] or level[a] != level[b])
        }
    }
}

// The motion vector table covers minus thirty-two to thirty-two in half samples, with no hole.
#test
{
    @assert(@countof(Mpeg4.MvdDelta) == 65)
    var seen: [65] bool = undefined
    for index in 65'u64 do
        seen[index] = false
    for index in @countof(Mpeg4.MvdDelta)
    {
        let delta = Mpeg4.MvdDelta[index]
        @assert(delta >= -32 and delta <= 32)
        @assert(!seen[cast(u64) (delta + 32)])
        seen[cast(u64) (delta + 32)] = true
    }
}

// Each scan order visits every position of an eight by eight block exactly once.
#test
{
    for order in 3'u32
    {
        let scan: const [..] u8 = order == 0 ? Mpeg4.ScanZigzag
                                  : (order == 1 ? Mpeg4.ScanAlternateHorizontal : Mpeg4.ScanAlternateVertical)
        @assert(@countof(scan) == 64)
        var seen: [64] bool = undefined
        for index in 64'u64 do
            seen[index] = false
        for index in 64'u64
        {
            @assert(scan[index] < 64)
            @assert(!seen[cast(u64) scan[index]])
            seen[cast(u64) scan[index]] = true
        }
    }

    // The zigzag begins the way every discrete cosine format's does.
    @assert(Mpeg4.ScanZigzag[0] == 0 and Mpeg4.ScanZigzag[1] == 1 and Mpeg4.ScanZigzag[2] == 8)
}

// The default quantiser weights are the ones clause 6.3.3 prints.
#test
{
    @assert(@countof(Mpeg4.DefaultIntraMatrix) == 64 and @countof(Mpeg4.DefaultInterMatrix) == 64)
    @assert(Mpeg4.DefaultIntraMatrix[0] == 8 and Mpeg4.DefaultIntraMatrix[63] == 45)
    @assert(Mpeg4.DefaultInterMatrix[0] == 16 and Mpeg4.DefaultInterMatrix[63] == 33)
    for index in 64'u64
    {
        @assert(Mpeg4.DefaultIntraMatrix[index] > 0)
        @assert(Mpeg4.DefaultInterMatrix[index] > 0)
    }
}

// The escape limits are not separate data.
//
// The standard prints them as Tables B.19 to B.22, but each is the largest level, or the largest
// run, the coefficient table itself holds for that key. Reproducing all four tabulations from the
// two coefficient tables is what says the coefficient tables are right: a wrong entry would move
// one of these maxima and no longer agree with what the standard printed.
#test
{
    // Table B.19: the intra levels, by run, for a coefficient that does not end its block.
    const IntraLevelMax: [15] u32 = [27, 10, 5, 4, 3, 3, 3, 3, 2, 2, 1, 1, 1, 1, 1]
    for run in 15'u32 do
        @assert(Mpeg4.levelMax(false, 0, run) == IntraLevelMax[cast(u64) run])

    // Table B.20: the same for an inter block, which codes longer runs and smaller levels.
    const InterLevelMax: [3] u32 = [12, 6, 4]
    for run in 3'u32 do
        @assert(Mpeg4.levelMax(true, 0, run) == InterLevelMax[cast(u64) run])

    // Table B.21 and B.22: the runs, by level.
    @assert(Mpeg4.runMax(false, 0, 1) == 14)
    @assert(Mpeg4.runMax(true, 0, 1) == 26)
    @assert(Mpeg4.runMax(true, 1, 1) == 40)

    // A key the table does not hold has no maximum, and the decoder must not widen against one.
    @assert(Mpeg4.levelMax(false, 0, 40) == 0)
    @assert(Mpeg4.levelMax(true, 1, 63) == 0)
}
