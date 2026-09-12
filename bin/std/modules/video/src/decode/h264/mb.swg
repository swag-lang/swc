//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 and 4:4:4 Baseline, Main, High, and High 4:4:4 Predictive streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, 4:2:2 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns macroblock syntax, residuals, motion data, and reconstruction scheduling.
//
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

// Extra motion regions are cold for the overwhelmingly common one-job macroblock.
struct MbExtraJobs
{
    jobs: [15] McJob
}

// Coefficients live outside the hot macroblock record. Inter skip macroblocks never touch this
// storage, while coded macroblocks index the matching entry in Decoder.parsedResiduals.
//
// A DC block keeps its levels in scan order, as they go through a transform of their own
// first. Every other block holds its coefficients dequantized and in raster order, so the
// inverse transform reads it in place.
struct MbResidual
{
    lumaDc:   [16] s16
    lumaAc:   [256] s16     // Sixteen coefficients per raster 4x4 block.
    luma8:    [256] s16     // Sixty-four coefficients per 8x8 quadrant.
    chromaDc: [8] s16       // Four per plane.
    chromaAc: [128] s16     // Sixteen per chroma block; the DC joins at reconstruction.
}

// The coefficients of the two colour planes of a 4:4:4 macroblock.
//
// A 4:4:4 colour plane is coded exactly as luma is, so it needs the whole of a luma plane's
// storage rather than the four small chroma blocks of a 4:2:0 macroblock. It lives apart from
// [[Video.H264.MbResidual]] because a 4:2:0 stream, which is nearly every stream, would
// otherwise pay for it at every macroblock of every picture.
struct MbResidual444
{
    dc: [32] s16      // Sixteen Intra_16x16 DC coefficients per plane.
    ac: [512] s16     // Sixteen coefficients per raster 4x4 block, per plane.
    t8: [512] s16     // Sixty-four coefficients per 8x8 quadrant, per plane.
}

// Where one colour plane of a macroblock keeps what it needs to be parsed and reconstructed.
//
// Luma answers with its own arrays and a 4:4:4 colour plane with the matching part of
// [[Video.H264.MbResidual444]], which is the whole of the difference between them: everything
// downstream of this takes the plane's storage and runs the same code.
struct PlaneResidual
{
    dc: [*] s16     // Sixteen Intra_16x16 DC coefficients.
    ac: [*] s16     // Sixteen coefficients per raster 4x4 block.
    t8: [*] s16     // Sixty-four coefficients per 8x8 quadrant.
    nz: [*] u8      // Nonzero counts per raster 4x4 block, with the CAVLC count semantics.
}

// One parsed macroblock, whatever the entropy coding. Its frequently scanned control and motion
// state remains compact; the large residual payload is cold for skipped inter macroblocks.
struct Mb
{
    mbX, mbY:     s32
    sliceIndex:   u32     // Reconstruction context in Decoder.pictureSlices.
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
    firstJob:     McJob
    extraJobs:    *MbExtraJobs?
    jobCount:     u32
    cbpLuma:      u32
    cbpChroma:    u32
    qp:           s32

    residual:    *MbResidual?
    residual444: *MbResidual444?     // The two colour planes of a 4:4:4 macroblock, if any.

    // Nonzero bookkeeping, CAVLC count semantics.
    nzLuma: [16] u8     // Per raster 4x4 block.

    // Per chroma block: four of them in 4:2:0, and the sixteen raster 4x4 blocks of the plane
    // in 4:4:4, where a colour plane carries as many blocks as luma.
    nzCb:        [16] u8
    nzCr:        [16] u8
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

// One macroblock next to the one being parsed: whether this slice decoded it, its summary, and
// where its blocks sit on the picture grids.
struct MbNeighbor
{
    available:  bool
    info:       *MbInfo?     // Null when unavailable.
    mbIndex:    u64
    blockBase:  u64     // Grid index of its top-left 4x4 block.
    chromaBase: u64     // Chroma grid index of its top-left chroma block.
}

// The macroblocks around the one being parsed, resolved once per macroblock.
//
// Every question a macroblock asks of its surroundings — a motion vector, a nonzero count, an
// intra mode, a context flag — used to re-derive this from absolute block coordinates: bounds,
// macroblock index, slice membership, class. Some three hundred thousand questions a picture
// concern the same four macroblocks, so they are answered from here with a block offset.
struct MbNeighbors
{
    a, b, c, d: MbNeighbor     // Left, top, top-right, top-left.
    blockBase:  u64            // Grid index of the current macroblock's top-left 4x4 block.
}

impl Slice
{
    // Resolves the macroblocks around the one at the current address, once per macroblock.
    mtd resolveNeighbors()
    {
        let dec = .dec!
        let sps = dec.sps!
        let mbX = .mbX
        let mbY = .mbY
        .neighbors.blockBase = cast(u64) (mbY * 4 * (sps.mbWidth * 4) + mbX * 4)
        .neighbors.a         = .resolveNeighbor(mbX - 1, mbY, mbX > 0)
        .neighbors.b         = .resolveNeighbor(mbX, mbY - 1, mbY > 0)
        .neighbors.c         = .resolveNeighbor(mbX + 1, mbY - 1, mbY > 0 and mbX + 1 < sps.mbWidth)
        .neighbors.d         = .resolveNeighbor(mbX - 1, mbY - 1, mbX > 0 and mbY > 0)
    }

    // Resolves one neighbor macroblock, available when it lies in the picture and this slice
    // decoded it.
    mtd const resolveNeighbor(mbX, mbY: s32, inPicture: bool)->MbNeighbor
    {
        var result: retval
        if not inPicture do
            return result

        let dec   = .dec!
        let sps   = dec.sps!
        let index = cast(u64) (mbY * sps.mbWidth + mbX)
        let info  = &dec.mbInfo[index]
        if info.sliceId != .sliceId do
            return result

        result.available  = true
        result.info       = info
        result.mbIndex    = index
        result.blockBase  = cast(u64) (mbY * 4 * (sps.mbWidth * 4) + mbX * 4)
        result.chromaBase = cast(u64) (mbY * 2 * (sps.mbWidth * 2) + mbX * 2)
        return result
    }

    // Reports whether the macroblock at `mbX`, `mbY` belongs to this slice's decoded region.
    mtd const mbAvailable(mbX, mbY: s32)->bool
    {
        let dec = .dec!
        let sps = dec.sps!
        if mbX < 0 or mbY < 0 or mbX >= sps.mbWidth or mbY >= sps.mbHeight do
            return false
        return dec.mbInfo[cast(u64) (mbY * sps.mbWidth + mbX)].sliceId == .sliceId
    }

    // Returns the macroblock info at a position the caller knows is valid.
    mtd const mbInfoAt(mbX, mbY: s32)->*MbInfo
    {
        let dec = .dec!
        return &dec.mbInfo[cast(u64) (mbY * dec.sps!.mbWidth + mbX)]
    }

    // Fetches the motion of the 4x4 block at `rx`, `ry` relative to the macroblock's top-left
    // block: `rx` runs from -1 to 4 and `ry` from -1 to 3, so the block lies in the macroblock
    // itself or in one of its four resolved neighbors.
    //
    // A block of the current macroblock is available once its motion is final; a block of
    // another macroblock once that macroblock belongs to the same slice. To the right of the
    // current macroblock nothing is decoded yet.
    mtd const motionAt(mb: *Mb, list: u32, rx, ry: s32)->NeighborMotion
    {
        var result: retval
        let dec = .dec!
        let gw  = dec.sps!.mbWidth * 4

        var neighbor: const *MbNeighbor?
        if ry < 0 do
            neighbor = rx < 0 ? &.neighbors.d : (rx >= 4 ? &.neighbors.c : &.neighbors.b)
        elif rx < 0 do
            neighbor = &.neighbors.a
        elif rx >= 4 do
            return result

        var index: u64
        if neighbor == null
        {
            // A block of the current macroblock contributes as soon as its motion for this
            // list is assigned, which is how earlier partitions feed the entropy contexts
            // and the prediction of later ones.
            if (mb.motionMask[list] & (1'u32 << cast(u32) (ry * 4 + rx))) == 0 do
                return result
            index = .neighbors.blockBase + cast(u64) (ry * gw + rx)
        }
        else
        {
            let other = neighbor
            if not other.available do
                return result
            let info = other.info!
            if info.class != MbClassInter
            {
                result.available = true
                result.intra     = true
                result.refIdx    = -1
                return result
            }

            if .header.type == SliceTypeP and info.skipped
            {
                let job = &dec.parsedMbs[other.mbIndex].firstJob
                result.available = true
                result.refIdx    = job.refIdx[list]
                result.mvX       = job.mv[list, 0]
                result.mvY       = job.mv[list, 1]
                return result
            }

            index = other.blockBase + cast(u64) ((ry & 3) * gw + (rx & 3))
        }

        result.available = true
        if list == 0
        {
            let motion = &dec.motionL0[index]
            result.refIdx = motion.refIdx
            result.mvX    = motion.mvX
            result.mvY    = motion.mvY
            result.mvdX   = dec.mvdL0[index * 2]
            result.mvdY   = dec.mvdL0[index * 2 + 1]
        }
        else
        {
            let motion = &dec.motionL1[index]
            result.refIdx = motion.refIdx
            result.mvX    = motion.mvX
            result.mvY    = motion.mvY
            result.mvdX   = dec.mvdL1[index * 2]
            result.mvdY   = dec.mvdL1[index * 2 + 1]
        }

        result.isDirect = dec.directFlags[index] != 0
        return result
    }

    // Median motion-vector prediction for one partition, section 8.4.1.3.
    //
    // `x4`, `y4` are macroblock-relative block coordinates, `w4`, `h4` the partition size in
    // blocks. `shapeHint` carries the 16x8/8x16 directional shortcuts: 0 none, 1 top 16x8,
    // 2 bottom 16x8, 3 left 8x16, 4 right 8x16.
    mtd predictMv(mb: *Mb, list: u32, x4, y4, w4: s32, refIdx: s32, shapeHint: u32)->[2] s16
    {
        let a = .motionAt(mb, list, x4 - 1, y4)
        let b = .motionAt(mb, list, x4, y4 - 1)
        var c = .motionAt(mb, list, x4 + w4, y4 - 1)
        if not c.available do
            c = .motionAt(mb, list, x4 - 1, y4 - 1)

        // Directional shortcuts for the two-partition shapes.
        switch shapeHint
        {
        case 1:
            if b.available and not b.intra and cast(s32) b.refIdx == refIdx do
                return [b.mvX, b.mvY]

        case 2:
            if a.available and not a.intra and cast(s32) a.refIdx == refIdx do
                return [a.mvX, a.mvY]

        case 3:
            if a.available and not a.intra and cast(s32) a.refIdx == refIdx do
                return [a.mvX, a.mvY]

        case 4:
            if c.available and not c.intra and cast(s32) c.refIdx == refIdx do
                return [c.mvX, c.mvY]

        default:
            break
        }

        // With only the left neighbor to go by, its motion is the prediction.
        if a.available and not b.available and not c.available do
            return [a.mvX, a.mvY]

        // A single neighbor sharing the reference wins over the median.
        let matchA = a.available and not a.intra and cast(s32) a.refIdx == refIdx
        let matchB = b.available and not b.intra and cast(s32) b.refIdx == refIdx
        let matchC = c.available and not c.intra and cast(s32) c.refIdx == refIdx
        if matchA and not matchB and not matchC do
            return [a.mvX, a.mvY]
        if matchB and not matchA and not matchC do
            return [b.mvX, b.mvY]
        if matchC and not matchA and not matchB do
            return [c.mvX, c.mvY]

        let medianX = maxS32(minS32(cast(s32) a.mvX, cast(s32) b.mvX), minS32(maxS32(cast(s32) a.mvX, cast(s32) b.mvX), cast(s32) c.mvX))
        let medianY = maxS32(minS32(cast(s32) a.mvY, cast(s32) b.mvY), minS32(maxS32(cast(s32) a.mvY, cast(s32) b.mvY), cast(s32) c.mvY))
        return [cast(s16) medianX, cast(s16) medianY]
    }

    // Stores the final motion of one partition into the picture grid and the parse state.
    mtd assignMotion(mb: *Mb, list: u32, x4, y4, w4, h4: s32, refIdx: s32, mv: [2] s16, mvd: [2] s16, isDirect: bool)
    {
        let dec   = .dec!
        let gw    = dec.sps!.mbWidth * 4
        let refId = refIdx >= 0 ? .refs[list, refIdx].identity : NoReferenceIdentity
        let entry = BlockMotion{mvX: mv[0], mvY: mv[1], refIdx: cast(s8) refIdx, refId: refId}
        let grid  = list == 0 ? dec.motionL0.storage() : dec.motionL1.storage()
        let diffs = list == 0 ? dec.mvdL0.storage() : dec.mvdL1.storage()
        for row in cast(u64) h4
        {
            for column in cast(u64) w4
            {
                let index = cast(u64) ((mb.mbY * 4 + y4 + cast(s32) row) * gw + mb.mbX * 4 + x4 + cast(s32) column)
                grid[index]            = entry
                diffs[index * 2]       = mvd[0]
                diffs[index * 2 + 1]   = mvd[1]
                dec.directFlags[index] = isDirect ? 1 : 0
            }
        }

        let rowMask = ((1'u32 << cast(u32) w4) - 1) << cast(u32) x4
        for row in cast(u32) h4
        {
            let mask = rowMask << cast(u32) ((y4 + cast(s32) row) * 4)
            mb.motionMask[list] |= mask
        }
    }

    // Publishes both reference lists of a skip or direct region in one grid pass. These modes
    // carry zero motion-vector differences, and writing the shared direct flag once avoids the
    // duplicate store made by two independent list assignments.
    mtd assignSkipMotion(mb: *Mb, x4, y4, w4, h4: s32, refIdx: [2] s8, mv0, mv1: [2] s16, isDirect: bool)
    {
        let dec    = .dec!
        let gw     = dec.sps!.mbWidth * 4
        let id0    = refIdx[0] >= 0 ? .refs[0, cast(u64) refIdx[0]].identity : NoReferenceIdentity
        let id1    = refIdx[1] >= 0 ? .refs[1, cast(u64) refIdx[1]].identity : NoReferenceIdentity
        let entry0 = BlockMotion{mvX: mv0[0], mvY: mv0[1], refIdx: refIdx[0], refId: id0}
        let entry1 = BlockMotion{mvX: mv1[0], mvY: mv1[1], refIdx: refIdx[1], refId: id1}
        if x4 == 0 and y4 == 0 and w4 == 4 and h4 == 4
        {
            // One block record is eight bytes, so one store publishes two blocks and two cover
            // a whole macroblock row of the grid.
            let refs0   = packedReferences(refIdx[0], id0)
            let refs1   = packedReferences(refIdx[1], id1)
            let pair0   = cast(Simd.S16x8) [mv0[0], mv0[1], refs0, 0's16, mv0[0], mv0[1], refs0, 0's16]
            let pair1   = cast(Simd.S16x8) [mv1[0], mv1[1], refs1, 0's16, mv1[0], mv1[1], refs1, 0's16]
            let zeros16 = Simd.splat(0's16)
            let direct  = Simd.splat(isDirect ? 1'u8 : 0)
            for row in 4'u64
            {
                let index = cast(u64) ((mb.mbY * 4 + cast(s32) row) * gw + mb.mbX * 4)
                let grid0 = cast([*] s16) (dec.motionL0.storage() + index)
                let grid1 = cast([*] s16) (dec.motionL1.storage() + index)
                Simd.store(grid0, pair0)
                Simd.store(grid0 + 8, pair0)
                Simd.store(grid1, pair1)
                Simd.store(grid1 + 8, pair1)
                Simd.store(dec.mvdL0.storage() + index * 2, zeros16)
                Simd.store(dec.mvdL1.storage() + index * 2, zeros16)
                Simd.storeLow4(dec.directFlags.storage() + index, direct)
            }

            mb.motionMask[0] |= 0xFFFF
            mb.motionMask[1] |= 0xFFFF
            return
        }

        for row in cast(u64) h4
        {
            for column in cast(u64) w4
            {
                let index = cast(u64) ((mb.mbY * 4 + y4 + cast(s32) row) * gw + mb.mbX * 4 + x4 + cast(s32) column)
                dec.motionL0[index]      = entry0
                dec.motionL1[index]      = entry1
                dec.mvdL0[index * 2]     = 0
                dec.mvdL0[index * 2 + 1] = 0
                dec.mvdL1[index * 2]     = 0
                dec.mvdL1[index * 2 + 1] = 0
                dec.directFlags[index]   = isDirect ? 1 : 0
            }
        }

        let rowMask = ((1'u32 << cast(u32) w4) - 1) << cast(u32) x4
        for row in cast(u32) h4
        {
            let mask = rowMask << cast(u32) ((y4 + cast(s32) row) * 4)
            mb.motionMask[0] |= mask
            mb.motionMask[1] |= mask
        }
    }

    // Adds one motion-compensation job.
    mtd addJob(mb: *Mb, x4, y4, w4, h4: s32, refIdx: [2] s8, mv0, mv1: [2] s16)
    {
        let job = .jobAt(mb, mb.jobCount)
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

    // Returns one motion region, keeping the common first region in the hot macroblock record.
    mtd jobAt(mb: *Mb, index: u32)->*McJob
    {
        if index == 0 do
            return &mb.firstJob

        if not mb.extraJobs
        {
            let dec = .dec!
            if dec.inlineRecon do
                mb.extraJobs = &.scratchExtraJobs
            else
            {
                let entry = dec.parsedExtraJobs.count
                dec.parsedExtraJobs.resize(entry + 1)
                mb.extraJobs = &dec.parsedExtraJobs[entry]
            }
        }

        return &mb.extraJobs.jobs[index - 1]
    }

    // Derives the motion of a P-skip macroblock, section 8.4.1.1.
    mtd deriveSkipP(mb: *Mb)
    {
        let a     = .motionAt(mb, 0, -1, 0)
        let b     = .motionAt(mb, 0, 0, -1)
        var mv: [2] s16
        let zeroA = a.available and not a.intra and a.refIdx == 0 and a.mvX == 0 and a.mvY == 0
        let zeroB = b.available and not b.intra and b.refIdx == 0 and b.mvX == 0 and b.mvY == 0
        if a.available and b.available and not zeroA and not zeroB do
            mv = .predictMv(mb, 0, 0, 0, 4, 0, 0)

        var zero:  [2] s16
        var noRef: [2] s8 = [0, -1]

        // A P-skip carries one uniform motion region. Neighbor prediction already reads that
        // region from `firstJob`, reconstruction consumes the job directly, and deblocking does
        // the same. Avoid publishing nineteen bytes of redundant 4x4-grid state per block on
        // the overwhelmingly common path of screen recordings.
        mb.motionMask[0] = 0xFFFF
        mb.motionMask[1] = 0xFFFF
        .addJob(mb, 0, 0, 4, 4, noRef, mv, zero)
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

    // Returns the macroblock's index in the picture, which the co-located records are kept by.
    mtd const colMbIndex(mb: *Mb)->u64 => cast(u64) (mb.mbY * .dec!.sps!.mbWidth + mb.mbX)

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
            let a = .motionAt(mb, list, -1, 0)
            let b = .motionAt(mb, list, 0, -1)
            var c = .motionAt(mb, list, 4, -1)
            if not c.available do
                c = .motionAt(mb, list, -1, -1)

            var minimum = -1's32
            if a.available and not a.intra and a.refIdx >= 0 do
                minimum = cast(s32) a.refIdx
            if b.available and not b.intra and b.refIdx >= 0 and (minimum < 0 or cast(s32) b.refIdx < minimum) do
                minimum = cast(s32) b.refIdx
            if c.available and not c.intra and c.refIdx >= 0 and (minimum < 0 or cast(s32) c.refIdx < minimum) do
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

        // A whole direct macroblock normally uses the same co-located zero decision in all four
        // quadrants. Publish and compensate it as one 16x16 region instead of constructing four
        // identical 8x8 jobs that reconstruction would merge again later.
        var knownColZeroMask = -1's32
        if quad < 0 and dec.sps!.direct8x8Inference
        {
            let dependsOnColZero = (refL0 == 0 and (mvL0[0] != 0 or mvL0[1] != 0)) or (refL1 == 0 and (mvL1[0] != 0 or mvL1[1] != 0))
            var uniform          = not dependsOnColZero
            var collapseZero     = false
            if dependsOnColZero
            {
                var mask = 0'u32
                for q in 4's32
                {
                    let colIndex = .colBlockIndex(mb, (q & 1) * 3, (q >> 1) * 3)
                    let motion   = col.colMotion(.colMbIndex(mb), colIndex)
                    if motion.ref == 0 and motion.isShort
                    {
                        let cx = cast(s32) motion.mv[0]
                        let cy = cast(s32) motion.mv[1]
                        if cx >= -1 and cx <= 1 and cy >= -1 and cy <= 1 do
                            mask |= 1'u32 << cast(u32) q
                    }
                }

                knownColZeroMask = cast(s32) mask
                uniform          = mask == 0 or mask == 15
                collapseZero     = mask == 15
            }

            if uniform
            {
                var blockMvL0 = mvL0
                var blockMvL1 = mvL1
                if refL0 < 0 or (refL0 == 0 and collapseZero) do
                    blockMvL0 = [0's16, 0's16]
                if refL1 < 0 or (refL1 == 0 and collapseZero) do
                    blockMvL1 = [0's16, 0's16]
                var refs: [2] s8 = [cast(s8) refL0, cast(s8) refL1]
                .assignSkipMotion(mb, 0, 0, 4, 4, refs, blockMvL0, blockMvL1, true)
                .addJob(mb, 0, 0, 4, 4, refs, blockMvL0, blockMvL1)
                return
            }
        }

        let quadFirst   = quad < 0 ? 0 : quad
        let quadLast    = quad < 0 ? 3 : quad
        let inference   = dec.sps!.direct8x8Inference
        var currentQuad = quadFirst
        while currentQuad <= quadLast
        {
            let qx = (currentQuad & 1) * 2
            let qy = (currentQuad >> 1) * 2

            // With 8x8 inference every cell of the quadrant reads the same co-located corner,
            // so the whole quadrant derives once and compensates as one job.
            let cellCount = inference ? 1's32 : 4's32
            for cell in cellCount
            {
                let bx   = inference ? qx : qx + (cell & 1)
                let by   = inference ? qy : qy + (cell >> 1)
                let span = inference ? 2's32 : 1's32

                // The co-located motion decides whether this block collapses to zero.
                var colX = bx
                var colY = by
                if inference
                {
                    colX = (currentQuad & 1) * 3
                    colY = (currentQuad >> 1) * 3
                }

                var colZero = false
                if knownColZeroMask >= 0
                {
                    colZero = (knownColZeroMask & (1 << currentQuad)) != 0
                }
                else
                {
                    let colIndex = .colBlockIndex(mb, colX, colY)
                    let motion   = col.colMotion(.colMbIndex(mb), colIndex)
                    if motion.ref == 0 and motion.isShort
                    {
                        let cx = cast(s32) motion.mv[0]
                        let cy = cast(s32) motion.mv[1]
                        colZero = cx >= -1 and cx <= 1 and cy >= -1 and cy <= 1
                    }
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
                var refs: [2] s8 = [cast(s8) refL0, cast(s8) refL1]
                .assignSkipMotion(mb, bx, by, span, span, refs, blockMvL0, blockMvL1, true)
                .addJob(mb, bx, by, span, span, refs, blockMvL0, blockMvL1)
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
        var currentQuad = quadFirst
        while currentQuad <= quadLast
        {
            let qx = (currentQuad & 1) * 2
            let qy = (currentQuad >> 1) * 2

            // With 8x8 inference the whole quadrant shares one co-located corner and one
            // scaled motion, so it derives once and compensates as one job.
            let cellCount = inference ? 1's32 : 4's32
            for cell in cellCount
            {
                let bx   = inference ? qx : qx + (cell & 1)
                let by   = inference ? qy : qy + (cell >> 1)
                let span = inference ? 2's32 : 1's32

                var colX = bx
                var colY = by
                if inference
                {
                    colX = (currentQuad & 1) * 3
                    colY = (currentQuad >> 1) * 3
                }

                let colIndex = .colBlockIndex(mb, colX, colY)
                let motion   = col.colMotion(.colMbIndex(mb), colIndex)
                var colMvX   = cast(s32) motion.mv[0]
                var colMvY   = cast(s32) motion.mv[1]
                var refL0    = 0's32
                var longTerm = false
                var poc0     = .refs[0, 0].poc
                if motion.ref < 0
                {
                    colMvX = 0
                    colMvY = 0
                }
                else
                {
                    // Map the co-located reference into the current list 0 by picture.
                    let wantedPoc = motion.poc
                    longTerm = not motion.isShort
                    var found = false
                    for index in .refCount[0] where .refs[0, index].poc == wantedPoc
                    {
                        refL0 = cast(s32) index
                        poc0  = .refs[0, index].poc
                        found = true
                        break
                    }

                    if not found
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

                var refs: [2] s8 = [cast(s8) refL0, 0]
                .assignSkipMotion(mb, bx, by, span, span, refs, mvL0, mvL1, true)
                .addJob(mb, bx, by, span, span, refs, mvL0, mvL1)
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
        .mbX    = cast(s32) (.mbAddr % cast(u32) sps.mbWidth)
        .mbY    = cast(s32) (.mbAddr / cast(u32) sps.mbWidth)
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

        let inter = .header.type != SliceTypeI
        while true
        {
            if .mbAddr >= mbCount do
                fail InvalidFormatError{"H.264 slice data runs past the end of the picture"}

            if inter and not .isCabac
            {
                var skipRun = .bits.ue()
                while skipRun > 0
                {
                    if .mbAddr >= mbCount do
                        fail InvalidFormatError{"H.264 skip run passes the end of the picture"}
                    .resolveNeighbors()
                    try .decodeSkipMb(&dec.parsedMbs[.mbAddr])
                    skipRun -= 1
                }

                if not .bits.moreData() do
                    break
                if .mbAddr >= mbCount do
                    fail InvalidFormatError{"H.264 slice data runs past the end of the picture"}
            }

            .resolveNeighbors()
            let mb = &dec.parsedMbs[.mbAddr]
            if inter and .isCabac and .decodeSkipFlagCabac()
            {
                try .decodeSkipMb(mb)
            }
            else
            {
                .prepareMb(mb)
                if .isCabac do
                    try .parseMbCabac(mb)
                else do
                    try .parseMbCavlc(mb)
                .bookkeepMb(mb)
                if dec.inlineRecon do
                    try .reconstructMb(mb)
                dec.decodedMbs += 1
                .advanceMb()
            }

            if .isCabac
            {
                if .terminate() != 0 do
                    break
                if .cabac.hasOverrun() do
                    fail InvalidFormatError{"H.264 slice data is truncated"}

                // What the arithmetic layer met and could not decode. It records instead of
                // raising: a bin reader whose caller asks whether the call failed pays an
                // opaque call at every residual block, and a macroblock holds twenty-seven of
                // them. One reading here costs nothing measurable and says the same thing.
                if .cabac.invalid do
                    fail InvalidFormatError{"H.264 macroblock syntax does not decode"}
            }
            elif not .bits.moreData()
            {
                break
            }
        }

        if not .isCabac and .bits.overran do
            fail InvalidFormatError{"H.264 slice data is truncated"}
        if dec.inlineRecon and .mbAddr >= mbCount do
            dec.completeInlinePicture()
    }

    // Resets the parse state for the macroblock at the current address.
    mtd prepareMb(mb: *Mb, clearResiduals: bool = true)
    {
        let dec = .dec!
        mb.mbX           = .mbX
        mb.mbY           = .mbY
        mb.sliceIndex    = cast(u32) .sliceId - 1
        mb.class         = MbClassInter
        mb.skipped       = false
        mb.transform8x8  = false
        mb.directMb      = false
        mb.decodedMask   = 0
        mb.motionMask[0] = 0
        mb.motionMask[1] = 0
        mb.extraJobs     = null
        mb.jobCount      = 0
        mb.cbpLuma       = 0
        mb.cbpChroma     = 0
        mb.chromaMode    = 0
        mb.i16Mode       = 0
        Memory.clear(&mb.nzLuma, #sizeof(mb.nzLuma))
        Memory.clear(&mb.nzCb, #sizeof(mb.nzCb))
        Memory.clear(&mb.nzCr, #sizeof(mb.nzCr))
        mb.residual444 = null
        Memory.clear(&mb.dcFlags, #sizeof(mb.dcFlags))
        Memory.clear(&mb.codedBlocks, #sizeof(mb.codedBlocks))
        Memory.set(&mb.refIdx, 0xFF, #sizeof(mb.refIdx))
        Memory.set(&mb.ctxRef, 0xFF, #sizeof(mb.ctxRef))
        Memory.clear(&mb.subType, #sizeof(mb.subType))
        Memory.clear(&mb.subShape, #sizeof(mb.subShape))
        Memory.clear(&mb.subDirect, #sizeof(mb.subDirect))

        if clearResiduals
        {
            // Full macroblocks can leave uncoded blocks untouched while parsing, and intra
            // reconstruction reads those blocks later. Skipped inter macroblocks have no
            // residual by definition, so their zero bookkeeping keeps these arrays unreachable.
            if dec.inlineRecon do
                mb.residual = &.scratchResidual
            else
            {
                let entry = dec.parsedResiduals.count
                dec.parsedResiduals.resize(entry + 1)
                mb.residual = &dec.parsedResiduals[entry]
            }

            Memory.set(&mb.intraModes, cast(u8) IntraDc, #sizeof(mb.intraModes))
            Memory.clear(mb.residual, #sizeof(MbResidual))

            if dec.sps!.is444()
            {
                if dec.inlineRecon do
                    mb.residual444 = &.scratchResidual444
                else
                {
                    let entry = dec.parsedResiduals444.count
                    dec.parsedResiduals444.resize(entry + 1)
                    mb.residual444 = &dec.parsedResiduals444[entry]
                }

                Memory.clear(mb.residual444, #sizeof(MbResidual444))
            }
        }
    }

    // Decodes one skipped macroblock.
    mtd decodeSkipMb(mb: *Mb) fail
    {
        let dec = .dec!
        if .header.type == SliceTypeP
        {
            // A P-skip never reads residual, intra, sub-partition, or per-block bookkeeping
            // from the parsed macroblock. Initialize only the compact state its motion,
            // reconstruction, and summary paths consume.
            mb.mbX           = .mbX
            mb.mbY           = .mbY
            mb.sliceIndex    = cast(u32) .sliceId - 1
            mb.class         = MbClassInter
            mb.skipped       = true
            mb.transform8x8  = false
            mb.directMb      = false
            mb.chromaMode    = 0
            mb.shape         = Shape16x16
            mb.motionMask[0] = 0
            mb.motionMask[1] = 0
            mb.extraJobs     = null
            mb.jobCount      = 0
            mb.cbpLuma       = 0
            mb.cbpChroma     = 0
            mb.qp            = .qp
            .deriveSkipP(mb)
        }
        else
        {
            .prepareMb(mb, clearResiduals: false)
            mb.skipped = true
            mb.shape   = Shape16x16
            mb.qp      = .qp
            .deriveDirect(mb, -1)
        }

        .lastQpDelta = 0
        .bookkeepMb(mb)
        if dec.inlineRecon do
            try .reconstructMb(mb)
        dec.decodedMbs += 1
        .advanceMb()
    }

    #[Swag.Inline]
    mtd advanceMb()
    {
        .mbAddr += 1
        .mbX    += 1
        if .mbX == .dec!.sps!.mbWidth
        {
            .mbX = 0
            .mbY += 1
            if .dec!.inlineRecon do
                .dec!.completeReconstructedRow(.mbY - 1)
            else do
                .dec!.scheduleParsedRows(cast(u32) .mbY)
        }
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
            try .parseIntraMb(mb, mbType, fromCabac: false)
        elif .header.type == SliceTypeP do
            try .parseInterMbP(mb, mbType)
        else do
            try .parseInterMbB(mb, mbType)

        if mb.class == MbClassIPcm do
            return

        // Coded block pattern for everything but Intra_16x16.
        if mb.class != MbClassIntra16x16
        {
            let code    = .bits.ue()
            let isIntra = mb.class == MbClassIntra4x4 or mb.class == MbClassIntra8x8

            // A pattern that names no chroma block is a shorter code with a mapping of its own,
            // Table 9-4 stating one column per chroma format.
            if dec.sps!.is444()
            {
                if code >= 16 do
                    fail InvalidFormatError{"H.264 coded block pattern does not decode"}
                mb.cbpLuma   = cast(u32) (isIntra ? GolombToIntraCbpNoChroma[code] : GolombToInterCbpNoChroma[code])
                mb.cbpChroma = 0
            }
            else
            {
                if code >= 48 do
                    fail InvalidFormatError{"H.264 coded block pattern does not decode"}
                let cbp = isIntra ? cast(u32) GolombToIntraCbp[code] : cast(u32) GolombToInterCbp[code]
                mb.cbpLuma   = cbp & 15
                mb.cbpChroma = cbp >> 4
            }

            // The inter 8x8 transform flag sits after the pattern.
            if mb.cbpLuma != 0 and pps.transform8x8 and mb.class == MbClassInter and not mb.skipped and .allowsTransform8x8(mb) do
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
        try .parseResidualCavlc(mb)
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
                if not .dec!.sps!.direct8x8Inference do
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
            try .parsePcm(mb)
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

            // The chroma part of the type says nothing in 4:4:4: the colour planes take the
            // luma pattern, and the residual syntax never reads a chroma pattern again.
            mb.cbpChroma = dec.sps!.is444() ? 0 : helper % 3
            mb.cbpLuma   = helper >= 3 ? 15 : 0
        }

        // A 4:4:4 colour plane is predicted with the luma modes of the macroblock, so no chroma
        // prediction mode is coded at all.
        if dec.sps!.is444() do
            return

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
        let modeA     = .neighborIntraMode(mb, bx - 1, by)
        let modeB     = .neighborIntraMode(mb, bx, by - 1)
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

    // Returns the intra prediction mode of the block at `rx`, `ry` relative to the macroblock:
    // -1 when the neighbor is missing, DC when it exists without per-block modes.
    mtd const neighborIntraMode(mb: *Mb, rx, ry: s32)->s32
    {
        if rx >= 0 and ry >= 0 do
            return cast(s32) mb.intraModes[cast(u64) (ry * 4 + rx)]

        let neighbor = rx < 0 ? &.neighbors.a : &.neighbors.b
        if not neighbor.available do
            return -1
        let dec = .dec!
        let neighborClass = neighbor.info!.class
        if neighborClass == MbClassInter and dec.pps!.constrainedIntra do
            return -1
        if neighborClass != MbClassIntra4x4 and neighborClass != MbClassIntra8x8 do
            return cast(s32) IntraDc
        return cast(s32) dec.intraModes[neighbor.blockBase + cast(u64) ((ry & 3) * (dec.sps!.mbWidth * 4) + (rx & 3))]
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

        let chromaMb = 16 >> dec.sps!.chromaShift()
        for plane in 2'u32
        {
            for row in chromaMb
            {
                for column in chromaMb do
                    frame.pixChroma(plane, mb.mbX * chromaMb + column, mb.mbY * chromaMb + row)[0] = cast(u8) .bits.read(8)
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
            try .parsePartitions(mb, 1)

        case 1:
            mb.shape = Shape16x8
            try .parsePartitions(mb, 2)

        case 2:
            mb.shape = Shape8x16
            try .parsePartitions(mb, 2)

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

            try .parseSubPartitions(mb, refZero: mbType == 4)
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

            try .parseSubPartitionsB(mb)
            return
        }

        // Table 7-14: two-partition and one-partition types with their list usage.
        mb.shape = BShapes[mbType]
        try .parsePartitionsB(mb, mbType)
    }

    // Parses references and vectors for P partitions; `count` is 1 or 2.
    mtd parsePartitions(mb: *Mb, count: u32) fail
    {
        var refs: [2] s32
        for part in cast(u64) count
        {
            refs[part] = try .parseRefIdx(mb, 0, cast(u32) part)
            .markCtxRef(mb, 0, cast(u32) part, refs[part])
        }

        for part in cast(u64) count
        {
            let geometry = .partGeometry(mb.shape, cast(u32) part)
            let mvd      = try .parseMvd(mb, 0, geometry.x4, geometry.y4)
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
        for index in mb.jobCount where .jobAt(mb, index).x == geometry.x4 * 4 and .jobAt(mb, index).y == geometry.y4 * 4
        {
            let job = .jobAt(mb, index)
            job.refIdx[list] = cast(s8) refIdx
            job.mv[list, 0]  = mv[0]
            job.mv[list, 1]  = mv[1]
            found = true
            break
        }

        if not found
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
            if not refZero do
                refs[quad] = try .parseSubRefIdx(mb, 0, cast(s32) quad)
            mb.ctxRef[0, quad] = cast(s8) refs[quad]
        }

        for quad in 4's32
        {
            try .parseSubMvs(mb, 0, quad, refs[quad])
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

            let mvd         = try .parseMvd(mb, list, x4, y4)
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
                for index in mb.jobCount where .jobAt(mb, index).x == x4 * 4 and .jobAt(mb, index).y == y4 * 4 and .jobAt(mb, index).width == w4 * 4 and .jobAt(mb, index).height == h4 * 4
                {
                    let job = .jobAt(mb, index)
                    job.refIdx[1] = cast(s8) refIdx
                    job.mv[1, 0]  = mv[0]
                    job.mv[1, 1]  = mv[1]
                    found         = true
                    break
                }

                if not found do
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
                    refs[list, part] = try .parseRefIdx(mb, list, part)
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
                    let mvd      = try .parseMvd(mb, list, geometry.x4, geometry.y4)
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
                    refs[list, quad] = try .parseSubRefIdx(mb, list, quad)
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
                    try .parseSubMvs(mb, list, quad, refs[list, quad])
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
        info.uniform      = mb.class == MbClassInter and mb.jobCount == 1 and mb.cbpLuma == 0

        if mb.skipped and .header.type == SliceTypeP
        {
            .bookkeepSkippedPMb(mb)
            return
        }

        let gw    = dec.sps!.mbWidth * 4
        let mbIdx = cast(u64) (mb.mbY * dec.sps!.mbWidth + mb.mbX)

        // The per-block state the next macroblocks' contexts and the filter read. A grid row of
        // four blocks is one 32-bit word, and the macroblock's own arrays are laid out the same
        // way, so a row moves as a word instead of four bytes.
        let perBlockModes = mb.class == MbClassIntra4x4 or mb.class == MbClassIntra8x8
        let dcModes       = IntraDc * 0x01010101
        let modeWords     = cast(const [*] u32) &mb.intraModes[0]
        let nzWords       = cast(const [*] u32) &mb.nzLuma[0]
        let codedWords    = cast(const [*] u32) &mb.codedBlocks[0]
        for row in 4'u64
        {
            let index = cast(u64) ((mb.mbY * 4 + cast(s32) row) * gw + mb.mbX * 4)
            (cast([*] u32) (dec.intraModes.storage() + index))[0]  = perBlockModes ? modeWords[row] : dcModes
            (cast([*] u32) (dec.nonZeroLuma.storage() + index))[0] = nzWords[row]
            (cast([*] u32) (dec.codedLuma.storage() + index))[0]   = codedWords[row]
        }

        // A 4:4:4 colour plane has one block per luma block, and its counts go out on the
        // luma grid so the entropy contexts of the next macroblock read them there.
        if dec.sps!.is444()
        {
            for block in 16's32
            {
                let index = cast(u64) ((mb.mbY * 4 + (block >> 2)) * gw + mb.mbX * 4 + (block & 3))
                dec.nonZeroCb[index] = mb.nzCb[cast(u64) block]
                dec.nonZeroCr[index] = mb.nzCr[cast(u64) block]
            }
        }
        else
        {
            let cw = dec.sps!.mbWidth * 2
            for block in 4's32
            {
                let index = cast(u64) ((mb.mbY * 2 + (block >> 1)) * cw + mb.mbX * 2 + (block & 1))
                dec.nonZeroCb[index] = mb.nzCb[cast(u64) block]
                dec.nonZeroCr[index] = mb.nzCr[cast(u64) block]
            }
        }

        dec.dcFlags[mbIdx * 3]     = mb.dcFlags[0]
        dec.dcFlags[mbIdx * 3 + 1] = mb.dcFlags[1]
        dec.dcFlags[mbIdx * 3 + 2] = mb.dcFlags[2]

        // Intra macroblocks leave a clean motion grid behind them. Four blocks of a grid row are
        // adjacent, so the whole row of records goes out in two stores.
        if mb.class != MbClassInter
        {
            // Four records of a grid row are adjacent, so a whole row goes out in two stores.
            let refs    = packedReferences(-1, NoReferenceIdentity)
            let clean   = cast(Simd.S16x8) [0's16, 0's16, refs, 0's16, 0's16, 0's16, refs, 0's16]
            let zeros16 = Simd.splat(0's16)
            let zeros8  = Simd.splat(0'u8)
            for row in 4's32
            {
                let index = cast(u64) ((mb.mbY * 4 + row) * gw + mb.mbX * 4)
                let grid0 = cast([*] s16) (dec.motionL0.storage() + index)
                let grid1 = cast([*] s16) (dec.motionL1.storage() + index)
                Simd.store(grid0, clean)
                Simd.store(grid0 + 8, clean)
                Simd.store(grid1, clean)
                Simd.store(grid1 + 8, clean)
                Simd.store(dec.mvdL0.storage() + index * 2, zeros16)
                Simd.store(dec.mvdL1.storage() + index * 2, zeros16)
                Simd.storeLow4(dec.directFlags.storage() + index, zeros8)
            }
        }

        // Export the motion the co-located prediction of later pictures reads. Only a reference
        // picture is ever read as a co-located one, so a picture nothing references — every
        // non-reference B picture of a pyramid — publishes none of it.
        if not dec.isRefPicture do
            return
        let frame = dec.current!
        frame.colUniform[mbIdx] = 0
        if mb.class == MbClassInter and mb.jobCount == 1
        {
            let job = &mb.firstJob
            var ref:   s8
            var mvX:   s16
            var mvY:   s16
            var poc:   s32
            var short: u8
            if job.refIdx[0] >= 0
            {
                ref   = job.refIdx[0]
                mvX   = job.mv[0, 0]
                mvY   = job.mv[0, 1]
                poc   = .refs[0, cast(u64) ref].poc
                short = .refs[0, cast(u64) ref].isLong ? 0 : 1
            }
            else
            {
                ref = job.refIdx[1]
                mvX = job.mv[1, 0]
                mvY = job.mv[1, 1]
                if ref >= 0
                {
                    poc   = .refs[1, cast(u64) ref].poc
                    short = .refs[1, cast(u64) ref].isLong ? 0 : 1
                }
            }

            // One motion for the whole macroblock: every row of the four arrays is the same
            // word or vector, so a row goes out in one store each.
            let refWord   = cast(u32) (cast #bit(u8) ref) * 0x01010101
            let shortWord = cast(u32) short * 0x01010101
            let mvRow     = cast(Simd.S16x8) [mvX, mvY, mvX, mvY, mvX, mvY, mvX, mvY]
            let pocRow    = Simd.splat(poc)
            for row in 4'u64
            {
                let index = cast(u64) ((mb.mbY * 4 + cast(s32) row) * gw + mb.mbX * 4)
                (cast([*] u32) (frame.colRef.storage() + index))[0]   = refWord
                (cast([*] u32) (frame.colShort.storage() + index))[0] = shortWord
                Simd.store(frame.colMv.storage() + index * 2, mvRow)
                Simd.store(frame.colPoc.storage() + index, pocRow)
            }

            return
        }

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

            let motion0 = &dec.motionL0[index]
            let ref0    = motion0.refIdx
            if ref0 >= 0
            {
                frame.colRef[index]        = ref0
                frame.colMv[index * 2]     = motion0.mvX
                frame.colMv[index * 2 + 1] = motion0.mvY
                frame.colPoc[index]        = .refs[0, ref0].poc
                frame.colShort[index]      = .refs[0, ref0].isLong ? 0 : 1
            }
            else
            {
                let motion1 = &dec.motionL1[index]
                let ref1    = motion1.refIdx
                frame.colRef[index]        = ref1
                frame.colMv[index * 2]     = motion1.mvX
                frame.colMv[index * 2 + 1] = motion1.mvY
                frame.colPoc[index]        = ref1 >= 0 ? .refs[1, ref1].poc : 0
                frame.colShort[index]      = ref1 >= 0 and not .refs[1, ref1].isLong ? 1 : 0
            }
        }
    }

    // Publishes the uniform metadata of a P-skip macroblock four blocks at a time.
    mtd bookkeepSkippedPMb(mb: *Mb)
    {
        let dec   = .dec!
        let job   = &mb.firstJob
        let ref   = job.refIdx[0]
        let poc   = ref >= 0 ? .refs[0, cast(u64) ref].poc : 0
        let gw    = dec.sps!.mbWidth * 4
        let zeros = Simd.splat(0'u8)
        for row in 4'u64
        {
            let index = cast(u64) ((mb.mbY * 4 + cast(s32) row) * gw + mb.mbX * 4)
            Simd.storeLow4(dec.codedLuma.storage() + index, zeros)
        }

        // Only a reference picture is read as a co-located one.
        if not dec.isRefPicture do
            return
        let frame        = dec.current!
        let compactIndex = cast(u64) (mb.mbY * dec.sps!.mbWidth + mb.mbX)
        frame.colUniform[compactIndex]      = 1
        frame.colMbMv[compactIndex * 2]     = job.mv[0, 0]
        frame.colMbMv[compactIndex * 2 + 1] = job.mv[0, 1]
        frame.colMbRef[compactIndex]        = ref
        frame.colMbPoc[compactIndex]        = poc
        frame.colMbShort[compactIndex]      = ref >= 0 and not .refs[0, cast(u64) ref].isLong ? 1 : 0
    }

    // Parses every residual block of the macroblock with CAVLC coding, section 7.3.5.3.
    mtd parseResidualCavlc(mb: *Mb) fail
    {
        // A 4:4:4 macroblock codes its colour planes exactly as luma, one whole plane after
        // another and all three under the same coded block pattern.
        let planes = .dec!.sps!.is444() ? 3'u32 : 1'u32
        for plane in planes do
            try .parsePlaneResidualCavlc(mb, plane)
        if planes > 1 do
            return

        // Chroma DC, both planes.
        if mb.cbpChroma != 0
        {
            for plane in 2'u64
            {
                let count = try residualCavlc(&.bits, -1, 4, (mb.residual!.chromaDc).buffer + plane * 4)
                mb.dcFlags[1 + plane] = count > 0 ? 1 : 0
            }
        }

        // Chroma AC, both planes.
        if mb.cbpChroma == 2
        {
            for plane in 2'u64
            {
                let scale = .dequantRow4(mb, cast(u32) plane + 1)
                for block in 4's32
                {
                    let nC    = .chromaNc(mb, cast(u32) plane, block & 1, block >> 1)
                    var levels: [16] s16
                    let count = try residualCavlc(&.bits, nC, 15, levels.buffer)
                    storeLevels(levels.buffer, 15, (mb.residual!.chromaAc).buffer + plane * 64 + cast(u64) block * 16, ResidualOrderAc, scale, 4)
                    if plane == 0 do
                        mb.nzCb[cast(u64) block] = cast(u8) count
                    else do
                        mb.nzCr[cast(u64) block] = cast(u8) count
                }
            }
        }
    }

    // Parses the residual of one colour plane coded with the luma syntax, section 7.3.5.3.2.
    //
    // Only luma feeds the deblocking strength: the boundary filter reads the luma transform
    // coefficients whatever the chroma format, so a colour plane writes its nonzero counts for
    // the entropy contexts and nothing else.
    mtd parsePlaneResidualCavlc(mb: *Mb, plane: u32) fail
    {
        let storage   = .planeResidual(mb, plane)
        let isIntra16 = mb.class == MbClassIntra16x16
        let isLuma    = plane == 0
        if isIntra16
        {
            let nC    = .planeNc(mb, plane, 0, 0)
            let count = try residualCavlc(&.bits, nC, 16, storage.dc)
            mb.dcFlags[cast(u64) plane] = count > 0 ? 1 : 0
            if count > 0 and isLuma
            {
                for block in 16'u64 do
                    mb.codedBlocks[block] = 1
            }
        }

        // Plane 4x4 or interleaved 8x8 blocks, one quadrant at a time.
        let scale4 = .dequantRow4(mb, plane)
        let scale8 = .dequantRow8(mb, plane)
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
                let nC     = .planeNc(mb, plane, bx, by)
                var levels: [16] s16
                var count:  u32
                if isIntra16
                {
                    count = try residualCavlc(&.bits, nC, 15, levels.buffer)
                    storeLevels(levels.buffer, 15, storage.ac + cast(u64) raster * 16, ResidualOrderAc, scale4, 4)
                }
                elif mb.transform8x8
                {
                    // CAVLC codes an 8x8 block as four interleaved 4x4 blocks: the levels of
                    // this cell sit at every fourth position of the 8x8 scan.
                    count = try residualCavlc(&.bits, nC, 16, levels.buffer)
                    let block = storage.t8 + cast(u64) quad * 64
                    for coefficient in 16'u64
                    {
                        let level = cast(s32) levels[coefficient]
                        if level == 0 do
                            continue
                        let position = cast(u64) ResidualOrder[ResidualOrder8x8 + coefficient * 4 + cast(u64) cell]
                        block[position] = dequantLevel(level, scale8[position], 6)
                    }
                }
                else
                {
                    count = try residualCavlc(&.bits, nC, 16, levels.buffer)
                    storeLevels(levels.buffer, 16, storage.ac + cast(u64) raster * 16, ResidualOrder4x4, scale4, 4)
                }

                storage.nz[cast(u64) raster] = cast(u8) count
                if count > 0
                {
                    if isLuma do
                        mb.codedBlocks[cast(u64) raster] = 1
                    quadAny = true
                }
            }

            // An 8x8 transform quadrant is one coded unit: any coefficient marks all four
            // cells for the deblocking strength.
            if mb.transform8x8 and quadAny and isLuma
            {
                for cell in 4's32
                {
                    let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                    mb.codedBlocks[cast(u64) raster] = 1
                }
            }
        }
    }

    // Returns the quantizer of one colour plane of `mb`: luma is 0, and the two chroma planes
    // (or the two 4:4:4 colour planes) are 1 and 2.
    mtd planeQp(mb: *Mb, plane: u32)->s32
    {
        if plane == 0 do
            return mb.qp
        return cast(s32) ChromaQp[cast(u64) Math.clamp(mb.qp + .pps!.chromaQpOffset[cast(u64) plane - 1], 0, 51)]
    }

    // Returns the 4x4 dequantization factors of one colour plane of `mb`, in raster order.
    mtd dequantRow4(mb: *Mb, plane: u32)->[*] u32
    {
        let list = cast(u64) plane + (mb.class == MbClassInter ? 3'u64 : 0'u64)
        return cast([*] u32) &.pps!.dequant4[list, cast(u64) .planeQp(mb, plane), 0]
    }

    // Returns the 8x8 dequantization factors of one colour plane of `mb`, in raster order;
    // the list is the plane's intra one of Table 7-2, or the inter one beside it.
    mtd dequantRow8(mb: *Mb, plane: u32)->[*] u32
    {
        let list = cast(u64) plane * 2 + (mb.class == MbClassInter ? 1'u64 : 0'u64)
        return cast([*] u32) &.pps!.dequant8[list, cast(u64) .planeQp(mb, plane), 0]
    }

    // Returns where one colour plane of `mb` keeps its coefficients and nonzero counts.
    mtd const planeResidual(mb: *Mb, plane: u32)->PlaneResidual
    {
        if plane == 0 do
            return {(mb.residual!.lumaDc).buffer, (mb.residual!.lumaAc).buffer, (mb.residual!.luma8).buffer, (mb.nzLuma).buffer}

        let side  = mb.residual444!
        let index = cast(u64) plane - 1
        return {
            (side.dc).buffer + index * 16,
            (side.ac).buffer + index * 256,
            (side.t8).buffer + index * 256,
            plane == 1 ? (mb.nzCb).buffer : (mb.nzCr).buffer}
    }

    // Returns what the coded block flag of an 8x8 transform block reads from the neighbour block
    // at `rx`, `ry` relative to the macroblock, section 9.3.3.1.1.9.
    //
    // An 8x8 block has a neighbouring block only where the neighbouring macroblock also takes
    // the 8x8 transform; one that takes the 4x4 transform holds no 8x8 block to answer with, and
    // contributes nothing rather than the flag of a 4x4 block. This rule is reachable only in
    // 4:4:4, where an 8x8 block codes a flag of its own at all.
    mtd const blockNz8x8(mb: *Mb, plane: u32, rx, ry: s32)->s32
    {
        let value = .blockNz(mb, plane, rx, ry)
        if value <= 0 or (rx >= 0 and ry >= 0) do
            return value

        let neighbor = rx < 0 ? &.neighbors.a : &.neighbors.b
        return neighbor.info!.transform8x8 ? value : 0
    }

    // Predicted nonzero count for the block of one colour plane at macroblock-relative
    // `bx`, `by`, section 9.2.1.
    mtd const planeNc(mb: *Mb, plane: u32, bx, by: s32)->s32
    {
        let a = .blockNz(mb, plane, bx - 1, by)
        let b = .blockNz(mb, plane, bx, by - 1)
        if a >= 0 and b >= 0 do
            return (a + b + 1) >> 1
        if a >= 0 do
            return a
        if b >= 0 do
            return b
        return 0
    }

    // Returns the stored nonzero count of one colour plane's block at `rx`, `ry` relative to the
    // macroblock, or -1 when it is unavailable.
    mtd const blockNz(mb: *Mb, plane: u32, rx, ry: s32)->s32
    {
        if rx >= 0 and ry >= 0
        {
            let local = cast(u64) (ry * 4 + rx)
            if plane == 0 do
                return cast(s32) mb.nzLuma[local]
            return cast(s32) (plane == 1 ? mb.nzCb[local] : mb.nzCr[local])
        }

        let neighbor = rx < 0 ? &.neighbors.a : &.neighbors.b
        if not neighbor.available do
            return -1
        if neighbor.info!.skipped do
            return 0

        let dec   = .dec!
        let index = neighbor.blockBase + cast(u64) ((ry & 3) * (dec.sps!.mbWidth * 4) + (rx & 3))
        if plane == 0 do
            return cast(s32) dec.nonZeroLuma[index]
        return cast(s32) (plane == 1 ? dec.nonZeroCb[index] : dec.nonZeroCr[index])
    }

    // Predicted nonzero count for one chroma block.
    mtd const chromaNc(mb: *Mb, plane: u32, bx, by: s32)->s32
    {
        let a = .chromaBlockNz(mb, plane, bx - 1, by)
        let b = .chromaBlockNz(mb, plane, bx, by - 1)
        if a >= 0 and b >= 0 do
            return (a + b + 1) >> 1
        if a >= 0 do
            return a
        if b >= 0 do
            return b
        return 0
    }

    // Returns the stored nonzero count of the chroma block at `rx`, `ry` relative to the
    // macroblock, or -1 when unavailable.
    mtd const chromaBlockNz(mb: *Mb, plane: u32, rx, ry: s32)->s32
    {
        if rx >= 0 and ry >= 0
        {
            let local = cast(u64) (ry * 2 + rx)
            return cast(s32) (plane == 0 ? mb.nzCb[local] : mb.nzCr[local])
        }

        let neighbor = rx < 0 ? &.neighbors.a : &.neighbors.b
        if not neighbor.available do
            return -1
        if neighbor.info!.skipped do
            return 0

        let dec   = .dec!
        let index = neighbor.chromaBase + cast(u64) ((ry & 1) * (dec.sps!.mbWidth * 2) + (rx & 1))
        return cast(s32) (plane == 0 ? dec.nonZeroCb[index] : dec.nonZeroCr[index])
    }
}

// Sentinel for "no reference" in a block's compact reference identity.
const NoReferenceIdentity = 0's8

// Returns the reference index and identity of a block record as the one 16-bit lane they occupy.
//
// A record is two vectors then these two bytes, so a packed store publishing whole records has
// to present them as a lane rather than as two fields.
#[Swag.Inline]
func packedReferences(refIdx, refId: s8)->s16
{
    return cast #bit (s16) (cast(u16) (cast #bit (u8) refIdx) | (cast(u16) (cast #bit (u8) refId) << 8))
}

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
