#global namespace H264
#global internal

using Core, Core.Errors

// The macroblock layer, sections 7.3.5 and 8.4: one entropy-independent parsed form, the
// motion derivations that fill it, and the slice decoding loop.

// Coded 4x4 block order to raster order inside a macroblock.
const CodedToRaster4: [16] u8 = [0, 1, 4, 5, 2, 3, 6, 7, 8, 9, 12, 13, 10, 11, 14, 15]

// Inter partition shapes of a macroblock.
const Shape16x16 = 0'u8
const Shape16x8  = 1'u8
const Shape8x16  = 2'u8
const Shape8x8   = 3'u8

// Sub-partition shapes of one 8x8 quadrant.
const Sub8x8 = 0'u8
const Sub8x4 = 1'u8
const Sub4x8 = 2'u8
const Sub4x4 = 3'u8

// Geometry of one inter partition, in 4x4 block units.
struct PartGeom
{
    x4:   s32
    y4:   s32
    w4:   s32
    h4:   s32
    hint: u32     // Directional prediction shortcut: 0 none, 1/2 top/bottom 16x8, 3/4 left/right 8x16.
}

// One motion-compensation region with its final motion.
struct McJob
{
    x, y:   s32     // Luma offset inside the macroblock.
    width:  s32
    height: s32
    refIdx: [2] s8
    mv:     [2, 2] s16
}

// One parsed macroblock, whatever the entropy coding.
struct Mb
{
    mbX, mbY:     s32
    class:        u8
    skipped:      bool
    transform8x8: bool
    directMb:     bool     // B_Direct_16x16.
    i16Mode:      u32
    chromaMode:   u32
    intraModes:   [16] u8     // Per raster 4x4 block.
    shape:        u8
    subShape:     [4] u8
    subType:      [4] u8     // Raw B sub-macroblock type, for its list usage.
    subDirect:    [4] bool
    ctxRef:       [2, 4] s8     // Parsed reference per quadrant, for the CABAC contexts.
    refIdx:       [2, 4] s8     // Per 8x8 quadrant; -1 when the list is unused.
    decodedMask:  u32           // Raster 4x4 blocks already reconstructed, for intra prediction.
    motionMask:   [2] u32       // Raster 4x4 blocks whose motion is assigned, per reference list.
    jobs:         [16] McJob
    jobCount:     u32
    cbpLuma:      u32
    cbpChroma:    u32
    qp:           s32

    // Residual coefficients in scan order, flattened.
    lumaDc:   [16] s16
    lumaAc:   [256] s16     // Sixteen coefficients per raster 4x4 block.
    luma8:    [256] s16     // Sixty-four coefficients per 8x8 quadrant.
    chromaDc: [8] s16       // Four per plane.
    chromaAc: [128] s16     // Sixteen per chroma block, scan positions 1..15.

    // Nonzero bookkeeping, CAVLC count semantics.
    nzLuma:      [16] u8     // Per raster 4x4 block.
    nzCb:        [4] u8
    nzCr:        [4] u8
    dcFlags:     [3] u8
    codedBlocks: [16] u8     // Any coefficient in the block, for deblocking.
}

// One neighbor's motion state.
struct NeighborMotion
{
    available: bool
    intra:     bool
    isDirect:  bool
    refIdx:    s8
    mvX:       s16
    mvY:       s16
    mvdX:      s16
    mvdY:      s16
}

impl Slice
{
    // Reports whether the macroblock at `mbX`, `mbY` belongs to this slice's decoded region.
    mtd const mbAvailable(mbX, mbY: s32)->bool
    {
        let dec = .dec!
        if mbX < 0 or mbY < 0 or mbX >= dec.sps!.mbWidth or mbY >= dec.sps!.mbHeight do
            return false
        return dec.mbInfo[cast(u64) (mbY * dec.sps!.mbWidth + mbX)].sliceId == .sliceId
    }

    // Returns the macroblock info at a position the caller knows is valid.
    mtd const mbInfoAt(mbX, mbY: s32)->*MbInfo
    {
        let dec = .dec!
        return &dec.mbInfo[cast(u64) (mbY * dec.sps!.mbWidth + mbX)]
    }

    // Fetches the motion of the 4x4 block at absolute grid position `x4`, `y4`.
    //
    // A block of the current macroblock is available once its motion is final; a block of
    // another macroblock once that macroblock belongs to the same slice.
    mtd const motionAt(mb: *Mb, list: u32, x4, y4: s32)->NeighborMotion
    {
        var result: retval
        let dec = .dec!
        let gw  = dec.sps!.mbWidth * 4
        if x4 < 0 or y4 < 0 or x4 >= gw or y4 >= dec.sps!.mbHeight * 4 do
            return result

        let nMbX = x4 >> 2
        let nMbY = y4 >> 2
        if nMbX == mb.mbX and nMbY == mb.mbY
        {
            // A block of the current macroblock contributes as soon as its motion for this
            // list is assigned, which is how earlier partitions feed the entropy contexts
            // and the prediction of later ones.
            let raster = cast(u32) ((y4 & 3) * 4 + (x4 & 3))
            if (mb.motionMask[list] & (1'u32 << raster)) == 0 do
                return result
        }
        elif dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)].sliceId != .sliceId
        {
            return result
        }
        elif dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)].class != MbClassInter
        {
            result.available = true
            result.intra     = true
            result.refIdx    = -1
            return result
        }

        let index = cast(u64) (y4 * gw + x4)
        result.available = true
        if list == 0
        {
            result.refIdx = dec.refIdxL0[index]
            result.mvX    = dec.mvL0[index * 2]
            result.mvY    = dec.mvL0[index * 2 + 1]
            result.mvdX   = dec.mvdL0[index * 2]
            result.mvdY   = dec.mvdL0[index * 2 + 1]
        }
        else
        {
            result.refIdx = dec.refIdxL1[index]
            result.mvX    = dec.mvL1[index * 2]
            result.mvY    = dec.mvL1[index * 2 + 1]
            result.mvdX   = dec.mvdL1[index * 2]
            result.mvdY   = dec.mvdL1[index * 2 + 1]
        }

        result.isDirect = dec.directFlags[index] != 0
        if nMbX == mb.mbX and nMbY == mb.mbY do
            return result

        // A block of a decoded neighbor may still be intra.
        if dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)].class != MbClassInter
        {
            result.intra  = true
            result.refIdx = -1
        }

        return result
    }

    // Median motion-vector prediction for one partition, section 8.4.1.3.
    //
    // `x4`, `y4` are macroblock-relative block coordinates, `w4`, `h4` the partition size in
    // blocks. `shapeHint` carries the 16x8/8x16 directional shortcuts: 0 none, 1 top 16x8,
    // 2 bottom 16x8, 3 left 8x16, 4 right 8x16.
    mtd predictMv(mb: *Mb, list: u32, x4, y4, w4: s32, refIdx: s32, shapeHint: u32)->[2] s16
    {
        let baseX = mb.mbX * 4 + x4
        let baseY = mb.mbY * 4 + y4
        let a     = .motionAt(mb, list, baseX - 1, baseY)
        let b     = .motionAt(mb, list, baseX, baseY - 1)
        var c     = .motionAt(mb, list, baseX + w4, baseY - 1)
        if !c.available do
            c = .motionAt(mb, list, baseX - 1, baseY - 1)

        // Directional shortcuts for the two-partition shapes.
        switch shapeHint
        {
        case 1:
            if b.available and !b.intra and cast(s32) b.refIdx == refIdx do
                return [b.mvX, b.mvY]

        case 2:
            if a.available and !a.intra and cast(s32) a.refIdx == refIdx do
                return [a.mvX, a.mvY]

        case 3:
            if a.available and !a.intra and cast(s32) a.refIdx == refIdx do
                return [a.mvX, a.mvY]

        case 4:
            if c.available and !c.intra and cast(s32) c.refIdx == refIdx do
                return [c.mvX, c.mvY]

        default:
            break
        }

        // With only the left neighbor to go by, its motion is the prediction.
        if a.available and !b.available and !c.available do
            return [a.mvX, a.mvY]

        // A single neighbor sharing the reference wins over the median.
        let matchA = a.available and !a.intra and cast(s32) a.refIdx == refIdx
        let matchB = b.available and !b.intra and cast(s32) b.refIdx == refIdx
        let matchC = c.available and !c.intra and cast(s32) c.refIdx == refIdx
        if matchA and !matchB and !matchC do
            return [a.mvX, a.mvY]
        if matchB and !matchA and !matchC do
            return [b.mvX, b.mvY]
        if matchC and !matchA and !matchB do
            return [c.mvX, c.mvY]

        let medianX = Math.max(Math.min(cast(s32) a.mvX, cast(s32) b.mvX), Math.min(Math.max(cast(s32) a.mvX, cast(s32) b.mvX), cast(s32) c.mvX))
        let medianY = Math.max(Math.min(cast(s32) a.mvY, cast(s32) b.mvY), Math.min(Math.max(cast(s32) a.mvY, cast(s32) b.mvY), cast(s32) c.mvY))
        return [cast(s16) medianX, cast(s16) medianY]
    }

    // Stores the final motion of one partition into the picture grid and the parse state.
    mtd assignMotion(mb: *Mb, list: u32, x4, y4, w4, h4: s32, refIdx: s32, mv: [2] s16, mvd: [2] s16, isDirect: bool)
    {
        let dec = .dec!
        let gw  = dec.sps!.mbWidth * 4
        for row in cast(u64) h4
        {
            for column in cast(u64) w4
            {
                let index = cast(u64) ((mb.mbY * 4 + y4 + cast(s32) row) * gw + mb.mbX * 4 + x4 + cast(s32) column)
                if list == 0
                {
                    dec.refIdxL0[index]      = cast(s8) refIdx
                    dec.mvL0[index * 2]      = mv[0]
                    dec.mvL0[index * 2 + 1]  = mv[1]
                    dec.mvdL0[index * 2]     = mvd[0]
                    dec.mvdL0[index * 2 + 1] = mvd[1]
                    dec.refPocL0[index]      = refIdx >= 0 ? .refs[0, refIdx].poc : NoRefPoc
                }
                else
                {
                    dec.refIdxL1[index]      = cast(s8) refIdx
                    dec.mvL1[index * 2]      = mv[0]
                    dec.mvL1[index * 2 + 1]  = mv[1]
                    dec.mvdL1[index * 2]     = mvd[0]
                    dec.mvdL1[index * 2 + 1] = mvd[1]
                    dec.refPocL1[index]      = refIdx >= 0 ? .refs[1, refIdx].poc : NoRefPoc
                }

                dec.directFlags[index] = isDirect ? 1 : 0
            }
        }

        for row in cast(u64) h4
        {
            for column in cast(u64) w4 do
                mb.motionMask[list] |= 1'u32 << cast(u32) ((y4 + cast(s32) row) * 4 + x4 + cast(s32) column)
        }
    }

    // Adds one motion-compensation job.
    mtd addJob(mb: *Mb, x4, y4, w4, h4: s32, refIdx: [2] s8, mv0, mv1: [2] s16)
    {
        let job = &mb.jobs[mb.jobCount]
        job.x        = x4 * 4
        job.y        = y4 * 4
        job.width    = w4 * 4
        job.height   = h4 * 4
        job.refIdx   = refIdx
        job.mv[0, 0] = mv0[0]
        job.mv[0, 1] = mv0[1]
        job.mv[1, 0] = mv1[0]
        job.mv[1, 1] = mv1[1]
        mb.jobCount  += 1
    }

    // Derives the motion of a P-skip macroblock, section 8.4.1.1.
    mtd deriveSkipP(mb: *Mb)
    {
        let a     = .motionAt(mb, 0, mb.mbX * 4 - 1, mb.mbY * 4)
        let b     = .motionAt(mb, 0, mb.mbX * 4, mb.mbY * 4 - 1)
        var mv: [2] s16
        let zeroA = a.available and !a.intra and a.refIdx == 0 and a.mvX == 0 and a.mvY == 0
        let zeroB = b.available and !b.intra and b.refIdx == 0 and b.mvX == 0 and b.mvY == 0
        if a.available and b.available and !zeroA and !zeroB do
            mv = .predictMv(mb, 0, 0, 0, 4, 0, 0)

        var mvd: [2] s16
        .assignMotion(mb, 0, 0, 0, 4, 4, 0, mv, mvd, false)
        .assignMotion(mb, 1, 0, 0, 4, 4, -1, mvd, mvd, false)
        var noRef: [2] s8 = [0, -1]
        .addJob(mb, 0, 0, 4, 4, noRef, mv, mvd)
    }

    // Derives the direct motion of a B macroblock region, section 8.4.1.2.
    //
    // `quad` selects one 8x8 quadrant, or -1 for the whole macroblock.
    mtd deriveDirect(mb: *Mb, quad: s32)
    {
        if .header.directSpatial do
            .deriveDirectSpatial(mb, quad)
        else do
            .deriveDirectTemporal(mb, quad)
    }

    // Returns the co-located 4x4 block index of the first list-1 reference for one block.
    mtd const colBlockIndex(mb: *Mb, x4, y4: s32)->u64
    {
        let dec = .dec!
        let gw  = dec.sps!.mbWidth * 4
        return cast(u64) ((mb.mbY * 4 + y4) * gw + mb.mbX * 4 + x4)
    }

    // Spatial direct prediction, section 8.4.1.2.2.
    mtd deriveDirectSpatial(mb: *Mb, quad: s32)
    {
        let dec = .dec!
        let col = .refs[1, 0].frame!

        // One reference pair and one prediction for the whole macroblock.
        var refL0 = -1's32
        var refL1 = -1's32
        for list in 2'u32
        {
            let a = .motionAt(mb, list, mb.mbX * 4 - 1, mb.mbY * 4)
            let b = .motionAt(mb, list, mb.mbX * 4, mb.mbY * 4 - 1)
            var c = .motionAt(mb, list, mb.mbX * 4 + 4, mb.mbY * 4 - 1)
            if !c.available do
                c = .motionAt(mb, list, mb.mbX * 4 - 1, mb.mbY * 4 - 1)

            var minimum = -1's32
            if a.available and !a.intra and a.refIdx >= 0 do
                minimum = cast(s32) a.refIdx
            if b.available and !b.intra and b.refIdx >= 0 and (minimum < 0 or cast(s32) b.refIdx < minimum) do
                minimum = cast(s32) b.refIdx
            if c.available and !c.intra and c.refIdx >= 0 and (minimum < 0 or cast(s32) c.refIdx < minimum) do
                minimum = cast(s32) c.refIdx
            if list == 0 do
                refL0 = minimum
            else do
                refL1 = minimum
        }

        var mvL0: [2] s16
        var mvL1: [2] s16
        let zeroPred = refL0 < 0 and refL1 < 0
        if zeroPred
        {
            refL0 = 0
            refL1 = 0
        }
        else
        {
            if refL0 >= 0 do
                mvL0 = .predictMv(mb, 0, 0, 0, 4, refL0, 0)
            if refL1 >= 0 do
                mvL1 = .predictMv(mb, 1, 0, 0, 4, refL1, 0)
        }

        let quadFirst   = quad < 0 ? 0 : quad
        let quadLast    = quad < 0 ? 3 : quad
        let inference   = dec.sps!.direct8x8Inference
        var mvd: [2] s16
        var currentQuad = quadFirst
        while currentQuad <= quadLast
        {
            let qx = (currentQuad & 1) * 2
            let qy = (currentQuad >> 1) * 2
            for cell in 4's32
            {
                let bx = qx + (cell & 1)
                let by = qy + (cell >> 1)

                // The co-located motion decides whether this block collapses to zero.
                var colX = mb.mbX * 4 + bx
                var colY = mb.mbY * 4 + by
                if inference
                {
                    colX = mb.mbX * 4 + (currentQuad & 1) * 3
                    colY = mb.mbY * 4 + (currentQuad >> 1) * 3
                }

                let colIndex = .colBlockIndex(mb, colX - mb.mbX * 4, colY - mb.mbY * 4)
                var colZero  = false
                if col.colRef[colIndex] == 0 and col.colShort[colIndex] != 0
                {
                    let cx = cast(s32) col.colMv[colIndex * 2]
                    let cy = cast(s32) col.colMv[colIndex * 2 + 1]
                    colZero = cx >= -1 and cx <= 1 and cy >= -1 and cy <= 1
                }

                var blockMvL0 = mvL0
                var blockMvL1 = mvL1
                if zeroPred
                {
                    blockMvL0 = [0's16, 0's16]
                    blockMvL1 = [0's16, 0's16]
                }
                else
                {
                    if refL0 == 0 and colZero do
                        blockMvL0 = [0's16, 0's16]
                    if refL1 == 0 and colZero do
                        blockMvL1 = [0's16, 0's16]
                }

                var zeroMv: [2] s16
                if refL0 < 0 do
                    blockMvL0 = zeroMv
                if refL1 < 0 do
                    blockMvL1 = zeroMv
                .assignMotion(mb, 0, bx, by, 1, 1, refL0, blockMvL0, mvd, true)
                .assignMotion(mb, 1, bx, by, 1, 1, refL1, blockMvL1, mvd, true)

                var refs: [2] s8 = [cast(s8) refL0, cast(s8) refL1]
                .addJob(mb, bx, by, 1, 1, refs, blockMvL0, blockMvL1)
            }

            currentQuad += 1
        }
    }

    // Temporal direct prediction, section 8.4.1.2.3.
    mtd deriveDirectTemporal(mb: *Mb, quad: s32)
    {
        let dec        = .dec!
        let col        = .refs[1, 0].frame!
        let currentPoc = dec.current!.poc

        let quadFirst   = quad < 0 ? 0 : quad
        let quadLast    = quad < 0 ? 3 : quad
        let inference   = dec.sps!.direct8x8Inference
        var mvd: [2] s16
        var currentQuad = quadFirst
        while currentQuad <= quadLast
        {
            let qx = (currentQuad & 1) * 2
            let qy = (currentQuad >> 1) * 2
            for cell in 4's32
            {
                let bx = qx + (cell & 1)
                let by = qy + (cell >> 1)

                var colX = bx
                var colY = by
                if inference
                {
                    colX = (currentQuad & 1) * 3
                    colY = (currentQuad >> 1) * 3
                }

                let colIndex = .colBlockIndex(mb, colX, colY)
                var colMvX   = cast(s32) col.colMv[colIndex * 2]
                var colMvY   = cast(s32) col.colMv[colIndex * 2 + 1]
                var refL0    = 0's32
                var longTerm = false
                var poc0     = .refs[0, 0].poc
                if col.colRef[colIndex] < 0
                {
                    colMvX = 0
                    colMvY = 0
                }
                else
                {
                    // Map the co-located reference into the current list 0 by picture.
                    let wantedPoc = col.colPoc[colIndex]
                    longTerm = col.colShort[colIndex] == 0
                    var found = false
                    for index in .refCount[0] where .refs[0, index].poc == wantedPoc
                    {
                        refL0 = cast(s32) index
                        poc0  = .refs[0, index].poc
                        found = true
                        break
                    }

                    if !found
                    {
                        refL0 = 0
                        poc0  = .refs[0, 0].poc
                    }
                }

                var mvL0: [2] s16
                var mvL1: [2] s16
                let poc1 = .refs[1, 0].poc
                let td   = Math.clamp(poc1 - poc0, -128, 127)
                if longTerm or td == 0 or .refs[0, refL0].isLong
                {
                    mvL0 = [cast(s16) colMvX, cast(s16) colMvY]
                    mvL1 = [0's16, 0's16]
                }
                else
                {
                    let tb    = Math.clamp(currentPoc - poc0, -128, 127)
                    let tx    = (16384 + Math.abs(td / 2)) / td
                    let scale = Math.clamp((tb * tx + 32) >> 6, -1024, 1023)
                    mvL0 = [cast(s16) ((scale * colMvX + 128) >> 8), cast(s16) ((scale * colMvY + 128) >> 8)]
                    mvL1 = [cast(s16) (cast(s32) mvL0[0] - colMvX), cast(s16) (cast(s32) mvL0[1] - colMvY)]
                }

                .assignMotion(mb, 0, bx, by, 1, 1, refL0, mvL0, mvd, true)
                .assignMotion(mb, 1, bx, by, 1, 1, 0, mvL1, mvd, true)
                var refs: [2] s8 = [cast(s8) refL0, 0]
                .addJob(mb, bx, by, 1, 1, refs, mvL0, mvL1)
            }

            currentQuad += 1
        }
    }

    // Decodes every macroblock of the slice.
    mtd decodeData() fail
    {
        let dec     = .dec!
        let sps     = dec.sps!
        let mbCount = cast(u32) (sps.mbWidth * sps.mbHeight)
        .mbAddr = .header.firstMb
        if .mbAddr >= mbCount do
            fail InvalidFormatError{"H.264 slice starts past the end of the picture"}

        if .isCabac
        {
            // The slice data starts at the next byte boundary.
            while .bits.bitPos & 7 != 0 do
                discard .bits.bit()
            let offset = .bits.bitPos >> 3
            .cabac.initContexts(.qp, .header.type, .header.cabacInitIdc)
            .cabac.start(.bits.data! + offset, .bits.size - offset)
        }

        var mb: Mb
        let inter = .header.type != SliceTypeI
        while true
        {
            if .mbAddr >= mbCount do
                fail InvalidFormatError{"H.264 slice data runs past the end of the picture"}

            if inter and !.isCabac
            {
                var skipRun = .bits.ue()
                while skipRun > 0
                {
                    if .mbAddr >= mbCount do
                        fail InvalidFormatError{"H.264 skip run passes the end of the picture"}
                    .decodeSkipMb(&mb)
                    skipRun -= 1
                }

                if !.bits.moreData() do
                    break
                if .mbAddr >= mbCount do
                    fail InvalidFormatError{"H.264 slice data runs past the end of the picture"}
            }

            if inter and .isCabac and .decodeSkipFlagCabac(&mb)
            {
                .decodeSkipMb(&mb)
            }
            else
            {
                .prepareMb(&mb)
                if .isCabac do
                    .parseMbCabac(&mb)
                else do
                    .parseMbCavlc(&mb)
                .reconstructMb(&mb)
                .bookkeepMb(&mb)
                dec.decodedMbs += 1
                .mbAddr        += 1
            }

            if .isCabac
            {
                if .cabac.terminate() != 0 do
                    break
                if .cabac.overran do
                    fail InvalidFormatError{"H.264 slice data is truncated"}
            }
            elif !.bits.moreData()
            {
                break
            }
        }

        if !.isCabac and .bits.overran do
            fail InvalidFormatError{"H.264 slice data is truncated"}
    }

    // Resets the parse state for the macroblock at the current address.
    mtd prepareMb(mb: *Mb)
    {
        let dec = .dec!
        mb.mbX           = cast(s32) (.mbAddr % cast(u32) dec.sps!.mbWidth)
        mb.mbY           = cast(s32) (.mbAddr / cast(u32) dec.sps!.mbWidth)
        mb.class         = MbClassInter
        mb.skipped       = false
        mb.transform8x8  = false
        mb.directMb      = false
        mb.decodedMask   = 0
        mb.motionMask[0] = 0
        mb.motionMask[1] = 0
        mb.jobCount      = 0
        mb.cbpLuma       = 0
        mb.cbpChroma     = 0
        mb.chromaMode    = 0
        mb.i16Mode       = 0
        for &value in mb.nzLuma do
            value[] = 0
        for &value in mb.nzCb do
            value[] = 0
        for &value in mb.nzCr do
            value[] = 0
        for &value in mb.dcFlags do
            value[] = 0
        for &value in mb.codedBlocks do
            value[] = 0
        for &value in mb.refIdx do
            value[] = -1
        for &value in mb.ctxRef do
            value[] = -1
        for &value in mb.subType do
            value[] = 0
        for &value in mb.subShape do
            value[] = 0
        for &value in mb.subDirect do
            value[] = false
        for &value in mb.intraModes do
            value[] = cast(u8) IntraDc
        for &value in mb.lumaDc do
            value[] = 0
        for &value in mb.lumaAc do
            value[] = 0
        for &value in mb.luma8 do
            value[] = 0
        for &value in mb.chromaDc do
            value[] = 0
        for &value in mb.chromaAc do
            value[] = 0
    }

    // Decodes one skipped macroblock.
    mtd decodeSkipMb(mb: *Mb) fail
    {
        let dec = .dec!
        .prepareMb(mb)
        mb.skipped   = true
        mb.shape     = Shape16x16
        mb.qp        = .qp
        .lastQpDelta = 0
        if .header.type == SliceTypeP do
            .deriveSkipP(mb)
        else do
            .deriveDirect(mb, -1)

        .reconstructMb(mb)
        .bookkeepMb(mb)
        dec.decodedMbs += 1
        .mbAddr        += 1
    }

    // Parses one full macroblock with CAVLC entropy coding.
    mtd parseMbCavlc(mb: *Mb) fail
    {
        let dec    = .dec!
        let pps    = dec.pps!
        var mbType = .bits.ue()

        // Fold the slice-type-specific type space onto the intra space.
        var isIntra = false
        if .header.type == SliceTypeI
        {
            isIntra = true
        }
        elif .header.type == SliceTypeP
        {
            if mbType >= 5
            {
                isIntra = true
                mbType  -= 5
            }
        }
        elif mbType >= 23
        {
            isIntra = true
            mbType  -= 23
        }

        if isIntra do
            .parseIntraMb(mb, mbType, fromCabac: false)
        elif .header.type == SliceTypeP do
            .parseInterMbP(mb, mbType)
        else do
            .parseInterMbB(mb, mbType)

        if mb.class == MbClassIPcm do
            return

        // Coded block pattern for everything but Intra_16x16.
        if mb.class != MbClassIntra16x16
        {
            let code = .bits.ue()
            if code >= 48 do
                fail InvalidFormatError{"H.264 coded block pattern does not decode"}
            let cbp = mb.class == MbClassIntra4x4 or mb.class == MbClassIntra8x8 ? cast(u32) GolombToIntraCbp[code] : cast(u32) GolombToInterCbp[code]
            mb.cbpLuma   = cbp & 15
            mb.cbpChroma = cbp >> 4

            // The inter 8x8 transform flag sits after the pattern.
            if mb.cbpLuma != 0 and pps.transform8x8 and mb.class == MbClassInter and !mb.skipped and .allowsTransform8x8(mb) do
                mb.transform8x8 = .bits.bit() != 0
        }

        if mb.cbpLuma != 0 or mb.cbpChroma != 0 or mb.class == MbClassIntra16x16
        {
            let delta = .bits.se()
            if delta < -26 or delta > 25 do
                fail InvalidFormatError{"H.264 macroblock QP delta is out of range"}
            .qp = (.qp + delta + 52) % 52
        }

        mb.qp = .qp
        .parseResidualCavlc(mb)
    }

    // Reports whether every inter partition of the macroblock is at least 8x8.
    mtd const allowsTransform8x8(mb: *Mb)->bool
    {
        if mb.directMb do
            return .dec!.sps!.direct8x8Inference
        if mb.shape != Shape8x8 do
            return true
        for quad in 4'u64
        {
            if mb.subDirect[quad]
            {
                if !.dec!.sps!.direct8x8Inference do
                    return false
            }
            elif mb.subShape[quad] != Sub8x8
            {
                return false
            }
        }

        return true
    }

    // Parses the prediction of an intra macroblock; `mbType` is already in the intra space.
    mtd parseIntraMb(mb: *Mb, mbType: u32, fromCabac: bool) fail
    {
        let dec = .dec!
        let pps = dec.pps!
        if mbType > 25 do
            fail InvalidFormatError{"H.264 intra macroblock type is out of range"}

        if mbType == 25
        {
            mb.class = MbClassIPcm
            .parsePcm(mb)
            return
        }

        if mbType == 0
        {
            // The 8x8 transform turns Intra_4x4 into Intra_8x8, with four coded modes.
            if pps.transform8x8
            {
                if fromCabac do
                    mb.transform8x8 = .transformFlagCabac(mb) != 0
                else do
                    mb.transform8x8 = .bits.bit() != 0
            }

            mb.class = mb.transform8x8 ? MbClassIntra8x8 : MbClassIntra4x4
            if mb.transform8x8
            {
                for quad in 4's32
                {
                    // The neighbor derivation anchors on the top-left 4x4 block of the
                    // quadrant, section 8.3.2.1.
                    let bx   = (quad & 1) * 2
                    let by   = (quad >> 1) * 2
                    let mode = .parseIntraMode(mb, by * 4 + bx, fromCabac)
                    mb.intraModes[cast(u64) (by * 4 + bx)]           = cast(u8) mode
                    mb.intraModes[cast(u64) (by * 4 + bx + 1)]       = cast(u8) mode
                    mb.intraModes[cast(u64) ((by + 1) * 4 + bx)]     = cast(u8) mode
                    mb.intraModes[cast(u64) ((by + 1) * 4 + bx + 1)] = cast(u8) mode
                }
            }
            else
            {
                for coded in 16's32
                {
                    let raster = cast(s32) CodedToRaster4[coded]
                    let mode   = .parseIntraMode(mb, raster, fromCabac)
                    mb.intraModes[cast(u64) raster] = cast(u8) mode
                }
            }
        }
        else
        {
            mb.class   = MbClassIntra16x16
            mb.i16Mode = (mbType - 1) % 4
            let helper = (mbType - 1) / 4
            mb.cbpChroma = helper % 3
            mb.cbpLuma   = helper >= 3 ? 15 : 0
        }

        if fromCabac do
            mb.chromaMode = .chromaModeCabac(mb)
        else
        {
            mb.chromaMode = .bits.ue()
            if mb.chromaMode > 3 do
                fail InvalidFormatError{"H.264 chroma prediction mode is out of range"}
        }
    }

    // Parses one intra 4x4 or 8x8 prediction mode; `raster` is the block's raster index.
    mtd parseIntraMode(mb: *Mb, raster: s32, fromCabac: bool)->u32
    {
        let bx = raster & 3
        let by = raster >> 2

        // The prediction is the smaller of the neighbor modes, section 8.3.1.1. A neighbor in
        // an available macroblock that is not Intra_4x4/8x8 contributes DC, but a missing
        // neighbor forces the whole prediction to DC: the -1 it reports wins the minimum.
        let modeA     = .neighborIntraMode(mb, mb.mbX * 4 + bx - 1, mb.mbY * 4 + by)
        let modeB     = .neighborIntraMode(mb, mb.mbX * 4 + bx, mb.mbY * 4 + by - 1)
        var predicted = Math.min(modeA, modeB)
        if predicted < 0 do
            predicted = cast(s32) IntraDc

        var mode: u32
        if fromCabac
        {
            mode = .intraModeCabac(cast(u32) predicted)
        }
        else
        {
            if .bits.bit() do
                mode = cast(u32) predicted
            else
            {
                let rem = .bits.read(3)
                mode = rem < cast(u32) predicted ? rem : rem + 1
            }
        }

        return mode
    }

    // Returns the intra prediction mode of the block at absolute position: -1 when the
    // neighbor is missing, DC when it exists without per-block modes.
    mtd const neighborIntraMode(mb: *Mb, x4, y4: s32)->s32
    {
        let dec = .dec!
        let gw  = dec.sps!.mbWidth * 4
        if x4 < 0 or y4 < 0 or x4 >= gw or y4 >= dec.sps!.mbHeight * 4 do
            return -1
        let nMbX = x4 >> 2
        let nMbY = y4 >> 2
        if nMbX == mb.mbX and nMbY == mb.mbY do
            return cast(s32) mb.intraModes[cast(u64) ((y4 & 3) * 4 + (x4 & 3))]
        if dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)].sliceId != .sliceId do
            return -1
        let neighborClass = dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)].class
        if neighborClass == MbClassInter and dec.pps!.constrainedIntra do
            return -1
        if neighborClass != MbClassIntra4x4 and neighborClass != MbClassIntra8x8 do
            return cast(s32) IntraDc
        return cast(s32) dec.intraModes[cast(u64) (y4 * gw + x4)]
    }

    // Reads the raw samples of an I_PCM macroblock.
    mtd parsePcm(mb: *Mb) fail
    {
        let dec   = .dec!
        let frame = dec.current!

        if .isCabac
        {
            // PCM samples are byte-aligned raw bits even in CABAC slices; the engine restarts
            // after them.
            fail UnsupportedFormatError{"video decoder does not support H.264 PCM macroblocks in CABAC slices"}
        }

        while .bits.bitPos & 7 != 0
        {
            if .bits.bit() != 0 do
                fail InvalidFormatError{"H.264 PCM alignment bits are not zero"}
        }

        for row in 16's32
        {
            for column in 16's32 do
                frame.pixLuma(mb.mbX * 16 + column, mb.mbY * 16 + row)[0] = cast(u8) .bits.read(8)
        }

        for plane in 2'u32
        {
            for row in 8's32
            {
                for column in 8's32 do
                    frame.pixChroma(plane, mb.mbX * 8 + column, mb.mbY * 8 + row)[0] = cast(u8) .bits.read(8)
            }
        }

        if .bits.overran do
            fail InvalidFormatError{"H.264 PCM macroblock is truncated"}

        // A PCM macroblock counts as fully coded for every prediction that looks at it.
        for &value in mb.nzLuma do
            value[] = 16
        for &value in mb.nzCb do
            value[] = 16
        for &value in mb.nzCr do
            value[] = 16
        for &value in mb.codedBlocks do
            value[] = 1
        mb.qp = .qp
    }

    // Parses the prediction of one P macroblock; `mbType` is the inter code 0..4.
    mtd parseInterMbP(mb: *Mb, mbType: u32) fail
    {
        if mbType > 4 do
            fail InvalidFormatError{"H.264 P macroblock type is out of range"}

        switch mbType
        {
        case 0:
            mb.shape = Shape16x16
            .parsePartitions(mb, 1)

        case 1:
            mb.shape = Shape16x8
            .parsePartitions(mb, 2)

        case 2:
            mb.shape = Shape8x16
            .parsePartitions(mb, 2)

        default:

            // P_8x8 and P_8x8ref0 differ only in reference coding.
            mb.shape = Shape8x8
            for quad in 4'u64
            {
                let sub = .isCabac ? .subMbTypePCabac() : .bits.ue()
                if sub > 3 do
                    fail InvalidFormatError{"H.264 P sub-partition type is out of range"}
                mb.subShape[quad]  = cast(u8) sub
                mb.subDirect[quad] = false
            }

            .parseSubPartitions(mb, refZero: mbType == 4)
        }
    }

    // Parses the prediction of one B macroblock; `mbType` is the inter code 0..22.
    mtd parseInterMbB(mb: *Mb, mbType: u32) fail
    {
        if mbType > 22 do
            fail InvalidFormatError{"H.264 B macroblock type is out of range"}

        if mbType == 0
        {
            mb.directMb = true
            mb.shape    = Shape16x16
            .deriveDirect(mb, -1)
            return
        }

        if mbType == 22
        {
            mb.shape = Shape8x8
            for quad in 4'u64
            {
                let sub = .isCabac ? .subMbTypeBCabac() : .bits.ue()
                if sub > 12 do
                    fail InvalidFormatError{"H.264 B sub-partition type is out of range"}
                mb.subType[quad] = cast(u8) sub
                if sub == 0
                {
                    mb.subDirect[quad] = true
                    mb.subShape[quad]  = Sub8x8
                }
                else
                {
                    mb.subDirect[quad] = false
                    mb.subShape[quad]  = BSubShape[sub]
                }
            }

            .parseSubPartitionsB(mb)
            return
        }

        // Table 7-14: two-partition and one-partition types with their list usage.
        mb.shape = BShapes[mbType]
        .parsePartitionsB(mb, mbType)
    }

    // Parses references and vectors for P partitions; `count` is 1 or 2.
    mtd parsePartitions(mb: *Mb, count: u32) fail
    {
        var refs: [2] s32
        for part in cast(u64) count
        {
            refs[part] = .parseRefIdx(mb, 0, cast(u32) part)
            .markCtxRef(mb, 0, cast(u32) part, refs[part])
        }

        for part in cast(u64) count
        {
            let geometry = .partGeometry(mb.shape, cast(u32) part)
            let mvd      = .parseMvd(mb, 0, geometry.x4, geometry.y4)
            .applyMotion(mb, 0, cast(u32) part, refs[part], mvd)

            // A P partition never uses list 1; writing that down keeps the deblocking
            // reference comparison off stale values from an earlier picture.
            var zero: [2] s16
            .assignMotion(mb, 1, geometry.x4, geometry.y4, geometry.w4, geometry.h4, -1, zero, zero, false)
        }
    }

    // Records the parsed reference of a partition for the entropy contexts of what follows.
    mtd markCtxRef(mb: *Mb, list: u32, part: u32, refIdx: s32)
    {
        let geometry = .partGeometry(mb.shape, part)
        for quadY in 2's32
        {
            for quadX in 2's32
            {
                let inPartX = quadX * 2 >= geometry.x4 and quadX * 2 < geometry.x4 + geometry.w4
                let inPartY = quadY * 2 >= geometry.y4 and quadY * 2 < geometry.y4 + geometry.h4
                if inPartX and inPartY do
                    mb.ctxRef[list, cast(u64) (quadY * 2 + quadX)] = cast(s8) refIdx
            }
        }
    }

    // Geometry of partition `part` for a one- or two-way shape.
    mtd const partGeometry(shape: u8, part: u32)->PartGeom
    {
        var result: retval
        result.w4 = 4
        result.h4 = 4
        if shape == Shape16x8
        {
            result.h4   = 2
            result.y4   = part == 0 ? 0 : 2
            result.hint = part == 0 ? 1 : 2
        }
        elif shape == Shape8x16
        {
            result.w4   = 2
            result.x4   = part == 0 ? 0 : 2
            result.hint = part == 0 ? 3 : 4
        }

        return result
    }

    // Applies one parsed partition motion: prediction plus difference, then the job.
    mtd applyMotion(mb: *Mb, list: u32, part: u32, refIdx: s32, mvd: [2] s16)
    {
        let geometry    = .partGeometry(mb.shape, part)
        let predicted   = .predictMv(mb, list, geometry.x4, geometry.y4, geometry.w4, refIdx, geometry.hint)
        var mv: [2] s16 = [cast(s16) (cast(s32) predicted[0] + cast(s32) mvd[0]), cast(s16) (cast(s32) predicted[1] + cast(s32) mvd[1])]
        .assignMotion(mb, list, geometry.x4, geometry.y4, geometry.w4, geometry.h4, refIdx, mv, mvd, false)

        // Jobs merge the two lists: the first list to arrive creates the job, the second
        // completes it.
        var found = false
        for index in mb.jobCount where mb.jobs[index].x == geometry.x4 * 4 and mb.jobs[index].y == geometry.y4 * 4
        {
            mb.jobs[index].refIdx[list] = cast(s8) refIdx
            mb.jobs[index].mv[list, 0]  = mv[0]
            mb.jobs[index].mv[list, 1]  = mv[1]
            found = true
            break
        }

        if !found
        {
            var refs: [2] s8 = [-1, -1]
            refs[list] = cast(s8) refIdx
            var zero: [2] s16
            .addJob(mb, geometry.x4, geometry.y4, geometry.w4, geometry.h4, refs, list == 0 ? mv : zero, list == 1 ? mv : zero)
        }
    }

    // Parses one reference index for `list`.
    mtd parseRefIdx(mb: *Mb, list: u32, part: u32)->s32 fail
    {
        let active = .refCount[list]
        if active <= 1 do
            return 0

        var value: u32
        if .isCabac
        {
            let geometry = .partGeometry(mb.shape, part)
            value = .refIdxCabac(mb, list, geometry.x4, geometry.y4)
        }
        elif active == 2
        {
            value = 1 - .bits.bit()
        }
        else
        {
            value = .bits.ue()
        }

        if value >= active do
            fail InvalidFormatError{"H.264 reference index exceeds the active reference count"}
        return cast(s32) value
    }

    // Parses one motion vector difference for a partition whose top-left block is at
    // `x4`, `y4`.
    mtd parseMvd(mb: *Mb, list: u32, x4, y4: s32)->[2] s16 fail
    {
        var result: retval
        if .isCabac
        {
            result = .mvdCabac(mb, list, x4, y4)
        }
        else
        {
            let x = .bits.se()
            let y = .bits.se()
            if x < -8192 or x > 8191 or y < -2048 or y > 2047 do
                fail InvalidFormatError{"H.264 motion vector difference is out of range"}
            result = [cast(s16) x, cast(s16) y]
        }

        return result
    }

    // Parses P_8x8 references and sub-partition vectors.
    mtd parseSubPartitions(mb: *Mb, refZero: bool) fail
    {
        var refs: [4] s32
        for quad in 4'u64
        {
            refs[quad] = 0
            if !refZero do
                refs[quad] = .parseSubRefIdx(mb, 0, cast(s32) quad)
            mb.ctxRef[0, quad] = cast(s8) refs[quad]
        }

        for quad in 4's32
        {
            .parseSubMvs(mb, 0, quad, refs[quad])
            var zero: [2] s16
            .assignMotion(mb, 1, (quad & 1) * 2, (quad >> 1) * 2, 2, 2, -1, zero, zero, false)
        }
    }

    // Parses one 8x8 quadrant's reference index.
    mtd parseSubRefIdx(mb: *Mb, list: u32, quad: s32)->s32 fail
    {
        let active = .refCount[list]
        if active <= 1 do
            return 0

        var value: u32
        if .isCabac
        {
            value = .refIdxCabac(mb, list, (quad & 1) * 2, (quad >> 1) * 2)
        }
        elif active == 2
        {
            value = 1 - .bits.bit()
        }
        else
        {
            value = .bits.ue()
        }

        if value >= active do
            fail InvalidFormatError{"H.264 reference index exceeds the active reference count"}
        return cast(s32) value
    }

    // Parses the vectors of one 8x8 quadrant, sub-block by sub-block.
    mtd parseSubMvs(mb: *Mb, list: u32, quad: s32, refIdx: s32) fail
    {
        let qx        = (quad & 1) * 2
        let qy        = (quad >> 1) * 2
        let shape     = mb.subShape[quad]
        var partCount = 1's32
        if shape == Sub8x4 or shape == Sub4x8 do
            partCount = 2
        elif shape == Sub4x4 do
            partCount = 4

        for part in partCount
        {
            var x4 = qx
            var y4 = qy
            var w4 = 2's32
            var h4 = 2's32
            switch shape
            {
            case Sub8x4:
                h4 = 1
                y4 += part

            case Sub4x8:
                w4 = 1
                x4 += part

            case Sub4x4:
                w4 = 1
                h4 = 1
                x4 += part & 1
                y4 += part >> 1

            default:
                break
            }

            let mvd         = .parseMvd(mb, list, x4, y4)
            let predicted   = .predictMv(mb, list, x4, y4, w4, refIdx, 0)
            var mv: [2] s16 = [cast(s16) (cast(s32) predicted[0] + cast(s32) mvd[0]), cast(s16) (cast(s32) predicted[1] + cast(s32) mvd[1])]
            .assignMotion(mb, list, x4, y4, w4, h4, refIdx, mv, mvd, false)

            var refs: [2] s8 = [-1, -1]
            refs[list] = cast(s8) refIdx
            var zero: [2] s16
            if list == 0 do
                .addJob(mb, x4, y4, w4, h4, refs, mv, zero)
            else
            {
                var found = false
                for index in mb.jobCount where mb.jobs[index].x == x4 * 4 and mb.jobs[index].y == y4 * 4 and mb.jobs[index].width == w4 * 4 and mb.jobs[index].height == h4 * 4
                {
                    mb.jobs[index].refIdx[1] = cast(s8) refIdx
                    mb.jobs[index].mv[1, 0]  = mv[0]
                    mb.jobs[index].mv[1, 1]  = mv[1]
                    found = true
                    break
                }

                if !found do
                    .addJob(mb, x4, y4, w4, h4, refs, zero, mv)
            }
        }
    }

    // Parses the two-partition and one-partition B macroblocks, Table 7-14.
    mtd parsePartitionsB(mb: *Mb, mbType: u32) fail
    {
        // Which lists each partition uses: bit 0 list 0, bit 1 list 1.
        let usage     = BListUsage[mbType]
        let partCount = mb.shape == Shape16x16 ? 1'u32 : 2'u32

        var refs: [2, 2] s32
        for list in 2'u32
        {
            for part in partCount
            {
                let use = (usage >> cast(u32) (part + list * 4)) & 1
                if use != 0
                {
                    refs[list, part] = .parseRefIdx(mb, list, part)
                    .markCtxRef(mb, list, part, refs[list, part])
                }
                else
                {
                    refs[list, part] = -1
                }
            }
        }

        // A partition that does not use a list writes its absence in the same pass, so a later
        // partition's contexts and prediction see it exactly as decoded order dictates.
        for list in 2'u32
        {
            for part in partCount
            {
                if refs[list, part] >= 0
                {
                    let geometry = .partGeometry(mb.shape, part)
                    let mvd      = .parseMvd(mb, list, geometry.x4, geometry.y4)
                    .applyMotion(mb, list, part, refs[list, part], mvd)
                }
                else
                {
                    let geometry = .partGeometry(mb.shape, part)
                    var zero: [2] s16
                    .assignMotion(mb, list, geometry.x4, geometry.y4, geometry.w4, geometry.h4, -1, zero, zero, false)
                }
            }
        }
    }

    // Parses B_8x8 references and sub-partition vectors.
    mtd parseSubPartitionsB(mb: *Mb) fail
    {
        var refs: [2, 4] s32
        for list in 2'u32
        {
            for quad in 4's32
            {
                refs[list, quad] = -1
                if mb.subDirect[quad] do
                    continue
                let sub = .bSubIndex(mb, quad)
                let use = (BSubListUsage[sub] >> list) & 1
                if use != 0
                {
                    refs[list, quad]                = .parseSubRefIdx(mb, list, quad)
                    mb.ctxRef[list, cast(u64) quad] = cast(s8) refs[list, quad]
                }
            }
        }

        // Direct quadrants derive before any vector parses, so their motion can serve as
        // prediction neighbors exactly as decoded order dictates.
        for quad in 4's32 where mb.subDirect[quad] do
            .deriveDirect(mb, quad)

        // A quadrant that does not use a list writes its absence in the same pass, so a later
        // quadrant's contexts and prediction see it exactly as decoded order dictates.
        for list in 2'u32
        {
            for quad in 4's32
            {
                if mb.subDirect[quad] do
                    continue
                if refs[list, quad] >= 0
                {
                    .parseSubMvs(mb, list, quad, refs[list, quad])
                }
                else
                {
                    var zero: [2] s16
                    .assignMotion(mb, list, (quad & 1) * 2, (quad >> 1) * 2, 2, 2, -1, zero, zero, false)
                }
            }
        }
    }

    // Returns the parsed sub-type index of a B quadrant, for its list usage.
    mtd const bSubIndex(mb: *Mb, quad: s32)->u64 => cast(u64) mb.subType[quad]

    // Writes the completed macroblock's summary for its neighbors and the filter.
    mtd bookkeepMb(mb: *Mb)
    {
        let dec  = .dec!
        let info = .mbInfoAt(mb.mbX, mb.mbY)
        info.class        = mb.class
        info.cbpLuma      = cast(u8) mb.cbpLuma
        info.cbpChroma    = cast(u8) mb.cbpChroma
        info.qp           = cast(u8) mb.qp
        info.chromaMode   = cast(u8) mb.chromaMode
        info.transform8x8 = mb.transform8x8
        info.skipped      = mb.skipped
        info.direct       = mb.directMb or (mb.skipped and .header.type == SliceTypeB)
        info.sliceId      = .sliceId
        info.deblockIdc   = cast(u8) .header.deblockIdc
        info.alphaOffset  = cast(s8) .header.alphaOffset
        info.betaOffset   = cast(s8) .header.betaOffset

        let gw    = dec.sps!.mbWidth * 4
        let mbIdx = cast(u64) (mb.mbY * dec.sps!.mbWidth + mb.mbX)
        for block in 16's32
        {
            let index = cast(u64) ((mb.mbY * 4 + (block >> 2)) * gw + mb.mbX * 4 + (block & 3))
            dec.intraModes[index]  = mb.class == MbClassIntra4x4 or mb.class == MbClassIntra8x8 ? mb.intraModes[cast(u64) block] : cast(u8) IntraDc
            dec.nonZeroLuma[index] = mb.nzLuma[cast(u64) block]
            dec.codedLuma[index]   = mb.codedBlocks[cast(u64) block]
        }

        let cw = dec.sps!.mbWidth * 2
        for block in 4's32
        {
            let index = cast(u64) ((mb.mbY * 2 + (block >> 1)) * cw + mb.mbX * 2 + (block & 1))
            dec.nonZeroCb[index] = mb.nzCb[cast(u64) block]
            dec.nonZeroCr[index] = mb.nzCr[cast(u64) block]
        }

        dec.dcFlags[mbIdx * 3]     = mb.dcFlags[0]
        dec.dcFlags[mbIdx * 3 + 1] = mb.dcFlags[1]
        dec.dcFlags[mbIdx * 3 + 2] = mb.dcFlags[2]

        // Intra macroblocks leave a clean motion grid behind them.
        if mb.class != MbClassInter
        {
            for block in 16's32
            {
                let index = cast(u64) ((mb.mbY * 4 + (block >> 2)) * gw + mb.mbX * 4 + (block & 3))
                dec.refIdxL0[index]      = -1
                dec.refIdxL1[index]      = -1
                dec.refPocL0[index]      = NoRefPoc
                dec.refPocL1[index]      = NoRefPoc
                dec.mvL0[index * 2]      = 0
                dec.mvL0[index * 2 + 1]  = 0
                dec.mvL1[index * 2]      = 0
                dec.mvL1[index * 2 + 1]  = 0
                dec.mvdL0[index * 2]     = 0
                dec.mvdL0[index * 2 + 1] = 0
                dec.mvdL1[index * 2]     = 0
                dec.mvdL1[index * 2 + 1] = 0
                dec.directFlags[index]   = 0
            }
        }

        // Export the motion the co-located prediction of later pictures reads.
        let frame = dec.current!
        for block in 16's32
        {
            let index = cast(u64) ((mb.mbY * 4 + (block >> 2)) * gw + mb.mbX * 4 + (block & 3))
            if mb.class != MbClassInter
            {
                frame.colRef[index]        = -1
                frame.colMv[index * 2]     = 0
                frame.colMv[index * 2 + 1] = 0
                frame.colPoc[index]        = 0
                frame.colShort[index]      = 0
                continue
            }

            let ref0 = dec.refIdxL0[index]
            if ref0 >= 0
            {
                frame.colRef[index]        = ref0
                frame.colMv[index * 2]     = dec.mvL0[index * 2]
                frame.colMv[index * 2 + 1] = dec.mvL0[index * 2 + 1]
                frame.colPoc[index]        = .refs[0, ref0].poc
                frame.colShort[index]      = .refs[0, ref0].isLong ? 0 : 1
            }
            else
            {
                let ref1 = dec.refIdxL1[index]
                frame.colRef[index]        = ref1
                frame.colMv[index * 2]     = dec.mvL1[index * 2]
                frame.colMv[index * 2 + 1] = dec.mvL1[index * 2 + 1]
                frame.colPoc[index]        = ref1 >= 0 ? .refs[1, ref1].poc : 0
                frame.colShort[index]      = ref1 >= 0 and !.refs[1, ref1].isLong ? 1 : 0
            }
        }
    }

    // Parses every residual block of the macroblock with CAVLC coding, section 7.3.5.3.
    mtd parseResidualCavlc(mb: *Mb) fail
    {
        let isIntra16 = mb.class == MbClassIntra16x16
        if isIntra16
        {
            let nC    = .lumaNc(mb, 0, 0)
            let count = residualCavlc(&.bits, nC, 16, @dataof(mb.lumaDc))
            mb.dcFlags[0] = count > 0 ? 1 : 0
            if count > 0
            {
                for block in 16'u64 do
                    mb.codedBlocks[block] = 1
            }
        }

        // Luma 4x4 or interleaved 8x8 blocks, one quadrant at a time.
        for quad in 4's32
        {
            if (mb.cbpLuma & (1'u32 << cast(u32) quad)) == 0 do
                continue
            var quadAny = false
            for cell in 4's32
            {
                let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                let bx     = raster & 3
                let by     = raster >> 2
                let nC     = .lumaNc(mb, bx, by)
                var count: u32
                if isIntra16
                {
                    count = residualCavlc(&.bits, nC, 15, @dataof(mb.lumaAc) + cast(u64) raster * 16 + 1)
                }
                elif mb.transform8x8
                {
                    // CAVLC codes an 8x8 block as four interleaved 4x4 blocks.
                    var cell16: [16] s16 = undefined
                    count = residualCavlc(&.bits, nC, 16, @dataof(cell16))
                    for coefficient in 16'u64 do
                        mb.luma8[cast(u64) quad * 64 + coefficient * 4 + cast(u64) cell] = cell16[coefficient]
                }
                else
                {
                    count = residualCavlc(&.bits, nC, 16, @dataof(mb.lumaAc) + cast(u64) raster * 16)
                }

                mb.nzLuma[cast(u64) raster] = cast(u8) count
                if count > 0
                {
                    mb.codedBlocks[cast(u64) raster] = 1
                    quadAny = true
                }
            }

            // An 8x8 transform quadrant is one coded unit: any coefficient marks all four
            // cells for the deblocking strength.
            if mb.transform8x8 and quadAny
            {
                for cell in 4's32
                {
                    let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                    mb.codedBlocks[cast(u64) raster] = 1
                }
            }
        }

        // Chroma DC, both planes.
        if mb.cbpChroma != 0
        {
            for plane in 2'u64
            {
                let count = residualCavlc(&.bits, -1, 4, @dataof(mb.chromaDc) + plane * 4)
                mb.dcFlags[1 + plane] = count > 0 ? 1 : 0
            }
        }

        // Chroma AC, both planes.
        if mb.cbpChroma == 2
        {
            for plane in 2'u64
            {
                for block in 4's32
                {
                    let nC    = .chromaNc(mb, cast(u32) plane, block & 1, block >> 1)
                    let count = residualCavlc(&.bits, nC, 15, @dataof(mb.chromaAc) + plane * 64 + cast(u64) block * 16 + 1)
                    if plane == 0 do
                        mb.nzCb[cast(u64) block] = cast(u8) count
                    else do
                        mb.nzCr[cast(u64) block] = cast(u8) count
                }
            }
        }
    }

    // Predicted nonzero count for the luma block at macroblock-relative `bx`, `by`,
    // section 9.2.1.
    mtd const lumaNc(mb: *Mb, bx, by: s32)->s32
    {
        let a = .blockNz(mb, mb.mbX * 4 + bx - 1, mb.mbY * 4 + by)
        let b = .blockNz(mb, mb.mbX * 4 + bx, mb.mbY * 4 + by - 1)
        if a >= 0 and b >= 0 do
            return (a + b + 1) >> 1
        if a >= 0 do
            return a
        if b >= 0 do
            return b
        return 0
    }

    // Returns the stored nonzero count of the luma block at an absolute position, or -1
    // when it is unavailable.
    mtd const blockNz(mb: *Mb, x4, y4: s32)->s32
    {
        let dec = .dec!
        let gw  = dec.sps!.mbWidth * 4
        if x4 < 0 or y4 < 0 or x4 >= gw or y4 >= dec.sps!.mbHeight * 4 do
            return -1
        let nMbX = x4 >> 2
        let nMbY = y4 >> 2
        if nMbX == mb.mbX and nMbY == mb.mbY do
            return cast(s32) mb.nzLuma[cast(u64) ((y4 & 3) * 4 + (x4 & 3))]
        if dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)].sliceId != .sliceId do
            return -1
        return cast(s32) dec.nonZeroLuma[cast(u64) (y4 * gw + x4)]
    }

    // Predicted nonzero count for one chroma block.
    mtd const chromaNc(mb: *Mb, plane: u32, bx, by: s32)->s32
    {
        let a = .chromaBlockNz(mb, plane, mb.mbX * 2 + bx - 1, mb.mbY * 2 + by)
        let b = .chromaBlockNz(mb, plane, mb.mbX * 2 + bx, mb.mbY * 2 + by - 1)
        if a >= 0 and b >= 0 do
            return (a + b + 1) >> 1
        if a >= 0 do
            return a
        if b >= 0 do
            return b
        return 0
    }

    // Returns the stored nonzero count of one chroma block, or -1 when unavailable.
    mtd const chromaBlockNz(mb: *Mb, plane: u32, x2, y2: s32)->s32
    {
        let dec = .dec!
        let cw  = dec.sps!.mbWidth * 2
        if x2 < 0 or y2 < 0 or x2 >= cw or y2 >= dec.sps!.mbHeight * 2 do
            return -1
        let nMbX = x2 >> 1
        let nMbY = y2 >> 1
        if nMbX == mb.mbX and nMbY == mb.mbY
        {
            let local = cast(u64) ((y2 & 1) * 2 + (x2 & 1))
            return cast(s32) (plane == 0 ? mb.nzCb[local] : mb.nzCr[local])
        }

        if dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)].sliceId != .sliceId do
            return -1
        let index = cast(u64) (y2 * cw + x2)
        return cast(s32) (plane == 0 ? dec.nonZeroCb[index] : dec.nonZeroCr[index])
    }
}

// Sentinel for "no reference" in the per-block reference picture-order array.
const NoRefPoc = Swag.S32.Min

// Partition shape of each B macroblock type 1..21, Table 7-14.
const BShapes: [23] u8 = [
    Shape16x16, Shape16x16, Shape16x16, Shape16x16,
    Shape16x8, Shape8x16, Shape16x8, Shape8x16, Shape16x8, Shape8x16,
    Shape16x8, Shape8x16, Shape16x8, Shape8x16, Shape16x8, Shape8x16,
    Shape16x8, Shape8x16, Shape16x8, Shape8x16, Shape16x8, Shape8x16,
    Shape8x8]

// List usage of each B macroblock type: bits 0..1 = partition 0/1 in list 0, bits 4..5 the
// same in list 1, Table 7-14.
const BListUsage: [23] u8 = [
    0x00,           // B_Direct_16x16, derived.
    0x01,           // B_L0_16x16.
    0x10,           // B_L1_16x16.
    0x11,           // B_Bi_16x16.
    0x03, 0x03,     // B_L0_L0_16x8, B_L0_L0_8x16.
    0x30, 0x30,     // B_L1_L1.
    0x21, 0x21,     // B_L0_L1.
    0x12, 0x12,     // B_L1_L0.
    0x23, 0x23,     // B_L0_Bi.
    0x32, 0x32,     // B_L1_Bi.
    0x13, 0x13,     // B_Bi_L0.
    0x31, 0x31,     // B_Bi_L1.
    0x33, 0x33,     // B_Bi_Bi.
    0x00]           // B_8x8, parsed separately.

// Sub-partition shape of each B sub-macroblock type, Table 7-18.
const BSubShape: [13] u8 = [
    Sub8x8,     // B_Direct_8x8.
    Sub8x8, Sub8x8, Sub8x8,
    Sub8x4, Sub4x8, Sub8x4, Sub4x8, Sub8x4, Sub4x8,
    Sub4x4, Sub4x4, Sub4x4]

// List usage of each B sub-macroblock type: bit 0 list 0, bit 1 list 1, Table 7-18.
const BSubListUsage: [13] u8 = [
    0,     // B_Direct_8x8, derived.
    1, 2, 3,
    1, 1, 2, 2, 3, 3,
    1, 2, 3]
