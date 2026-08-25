//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns decoder state, the macroblock layer, intra prediction, and picture reconstruction.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors, Pixel

// What a neighbour that is missing, or not intra, contributes to a prediction, clause 7.4.3.1.
const DefaultNeighbourDc = 1024's32

// Derived macroblock types, clause 6.3.7. Five is the stuffing code, which carries no macroblock.
const TypeInter    = 0'u32
const TypeInterQ   = 1'u32
const TypeInter4V  = 2'u32
const TypeIntra    = 3'u32
const TypeIntraQ   = 4'u32
const TypeStuffing = 5'u32

// Bidirectional macroblock types, Table B.4, in the order their codes name them.
const TypeDirect       = 0'u32
const TypeInterpolated = 1'u32
const TypeBackward     = 2'u32
const TypeForward      = 3'u32

// What one block leaves behind for the blocks that predict from it.
struct BlockState
{
    dc:    s32          // The reconstructed direct current, before the transform.
    row:   [7] s16      // The first row of quantised coefficients, after prediction.
    col:   [7] s16      // The first column.
    quant: u8
    intra: bool
}

// What one macroblock leaves behind for the macroblocks that predict from it.
struct MacroblockState
{
    vectors: [4] Vector
    intra:   bool
    coded:   bool
}

// Decodes one MPEG-4 Part 2 elementary stream, one plane at a time.
#[Swag.NoCopy]
struct Decoder
{
    layer:       Layer
    anchorOld:   Frame                    // The older of the two planes a bidirectional one sits between.
    anchorNew:   Frame                    // The last intra or predicted plane, which a predicted one refers to.
    current:     Frame
    blocks:      Array'BlockState         // Six per macroblock, in decoding order.
    macroblocks: Array'MacroblockState
    coLocated:   Array'MacroblockState    // The macroblocks of `anchorNew`, for the direct mode.
    quant:       u32
    packetStart: u64                      // The first macroblock of the packet being read.
    anchors:     u32                      // How many anchors have been decoded, saturating at two.
    oldTime:     s64                      // Container timestamps of the two anchors and this plane.
    newTime:     s64
    planeTime:   s64
    forward:     Vector                   // The running vector predictors of a bidirectional plane.
    backward:    Vector
    blend:       [64] u8
    showsCurrent: bool                    // The last plane decoded is in `current` rather than in an anchor.
}

impl Decoder
{
    // Reads the setup headers a container carries beside the stream.
    mtd configure(config: const [..] u8) fail
    {
        discard try .readStartCodes(config, null)
        if !.layer.configured do
            fail InvalidFormatError{"MPEG-4 decoder configuration holds no video object layer"}
    }

    // Walks the start codes of one byte run, reading what each introduces.
    //
    // When `header` is given, a video object plane stops the walk and its header is read into it;
    // the plane payload starts where the reader was left.
    mtd readStartCodes(bytes: const [..] u8, header: #null *PlaneHeader)->u64 fail
    {
        var at = nextStartCode(bytes, 0)
        while at + 4 <= @countof(bytes)
        {
            let code = cast(u32) bytes[at + 3]
            let body = at + 4
            if code == CodeVop
            {
                if !header do
                    return body
                if !.layer.configured do
                    fail InvalidFormatError{"MPEG-4 plane arrived before its layer"}
                var reader = BitReader.create(bytes[body until @countof(bytes)])
                try readPlaneHeader(&.layer, &reader, header)
                return body * 8 + reader.bitPos
            }

            if code >= 0x20 and code <= 0x2F
            {
                var reader = BitReader.create(bytes[body until @countof(bytes)])
                try .layer.readVideoObjectLayer(&reader)
            }

            at = nextStartCode(bytes, body)
        }

        return @countof(bytes) * 8
    }

    // Decodes one access unit and returns whether a picture came out of it.
    //
    // A plane the stream marks as not coded repeats the one before it, which is what a stream
    // says when nothing moved.
    mtd decodeSample(bytes: const [..] u8, presentationTime: s64)->bool fail
    {
        .planeTime = presentationTime
        var header: PlaneHeader
        let bitAt = try .readStartCodes(bytes, &header)
        if !.layer.configured do
            fail InvalidFormatError{"MPEG-4 sample arrived before its video object layer"}

        .allocate()
        if !header.coded
        {
            // A plane that codes nothing repeats the anchor before it.
            return .anchors != 0
        }

        if header.codingType == VopSprite do
            fail UnsupportedFormatError{"video decoder does not read MPEG-4 sprite planes"}
        if header.codingType == VopPredicted and !.anchors do
            return false
        if header.codingType == VopBidirectional and .anchors < 2 do
            return false

        var reader = BitReader.create(bytes)
        reader.bitPos = bitAt
        try .decodePlane(&reader, &header)

        if header.codingType == VopBidirectional
        {
            // A bidirectional plane is shown and forgotten: no plane refers back to it.
            .showsCurrent = true
            return true
        }

        // An intra or predicted plane becomes the newer anchor, and the newer becomes the older.
        .rotateAnchors()
        .showsCurrent = false
        return true
    }

    // Moves the picture just decoded into the anchor pair.
    mtd rotateAnchors()
    {
        var temp: Frame = #move .anchorOld
        .anchorOld = #move .anchorNew
        .anchorNew = #move .current
        .current   = #move temp

        for index in .macroblocks.count do
            .coLocated[index] = .macroblocks[index]
        .oldTime = .newTime
        .newTime = .planeTime
        .anchors = Math.min(.anchors + 1, 2'u32)
    }

    // The picture the last call produced.
    mtd reference()->*Frame => .showsCurrent ? &.current : &.anchorNew

    // Sizes the pictures and the prediction state for the layer geometry.
    mtd allocate()
    {
        let coded = .layer.mbWidth * 16
        let rows  = .layer.mbHeight * 16
        .anchorOld.prepare(coded, rows, .layer.width, .layer.height)
        .anchorNew.prepare(coded, rows, .layer.width, .layer.height)
        .current.prepare(coded, rows, .layer.width, .layer.height)

        let count = cast(u64) .layer.mbWidth * cast(u64) .layer.mbHeight
        .blocks.resize(count * 6)
        .macroblocks.resize(count)
        .coLocated.resize(count)
    }

    // Forgets every reference, which is what a seek to a random access point needs.
    mtd reset()
    {
        .anchors = 0
    }

    // The state of one block of one macroblock, or the default when it is outside the picture.
    mtd const neighbour(mbX, mbY: s32, block: u64)->BlockState
    {
        var result: retval
        result.dc    = DefaultNeighbourDc
        result.quant = cast(u8) .quant
        if mbX < 0 or mbY < 0 or mbX >= cast(s32) .layer.mbWidth or mbY >= cast(s32) .layer.mbHeight do
            return result

        let macroblock = cast(u64) mbY * cast(u64) .layer.mbWidth + cast(u64) mbX
        if macroblock < .packetStart do
            return result
        return .blocks[macroblock * 6 + block]
    }

    // Decodes one video object plane into `current`.
    //
    // A plane may be cut into video packets, each announced by a resync marker and a header of
    // its own. A packet starts a fresh prediction: nothing before it may be predicted from, and
    // its header may move the quantiser and the thresholds the rest of the plane reads with.
    mtd decodePlane(reader: *BitReader, header: const *PlaneHeader) fail
    {
        var active = header[]
        .quant       = active.quant
        .packetStart = 0
        .forward     = Vector{}
        .backward    = Vector{}

        let total = cast(u64) .layer.mbWidth * cast(u64) .layer.mbHeight
        var index = 0'u64
        while index < total
        {
            if index and !.layer.resyncDisabled
            {
                let after = .findResyncMarker(reader, &active)
                if after >= 0
                {
                    reader.bitPos = cast(u64) after
                    try .readPacketHeader(reader, &active, &index)
                    .packetStart = index
                    .forward     = Vector{}
                    .backward    = Vector{}
                    if index >= total do
                        break
                }
            }

            try .decodeMacroblock(reader, &active, cast(s32) (index % cast(u64) .layer.mbWidth),
                                  cast(s32) (index / cast(u64) .layer.mbWidth))
            index += 1
        }

        // Motion compensation reads through the padding rather than clamping, so the padding has
        // to hold what a clamp would have produced.
        .current.extendEdges()

        let probe = .current.lumaOrigin()
    }

    // Reads one bit of the reader without moving it.
    mtd const peekBit(reader: const *BitReader, at: u64)->u32
    {
        if at >= reader.bitEnd do
            return 0
        return cast(u32) (reader.data![at >> 3] >> (7 - cast(u32) (at & 7))) & 1
    }

    // How long the marker that opens a video packet is, clause 6.3.3.
    mtd const resyncMarkerBits(header: const *PlaneHeader)->u32
    {
        if header.codingType == VopIntra do
            return 17
        if header.codingType == VopBidirectional do
            return Math.max(15 + Math.max(header.fcodeForward, header.fcodeBackward), 17'u32) + 1
        return 16 + header.fcodeForward
    }

    // Returns the bit position past a resync marker at the reader, or minus one when there is
    // none there.
    //
    // A marker is byte aligned, and the encoder pads up to that boundary with a zero followed by
    // ones. The marker itself is a run of zeros closed by a one, which no macroblock can produce.
    mtd const findResyncMarker(reader: const *BitReader, header: const *PlaneHeader)->s64
    {
        // The stuffing is always there, even when the position is already on a byte: a zero, then
        // ones up to the next boundary. That is what makes the pattern impossible to mistake for
        // macroblock data.
        var at = reader.bitPos
        if .peekBit(reader, at) != 0 do
            return -1
        at += 1
        while (at & 7) != 0
        {
            if .peekBit(reader, at) != 1 do
                return -1
            at += 1
        }

        let bits = cast(u64) .resyncMarkerBits(header)
        if at + bits > reader.bitEnd do
            return -1
        for index in bits - 1 where .peekBit(reader, at + index) != 0 do
            return -1
        if .peekBit(reader, at + bits - 1) != 1 do
            return -1
        return cast(s64) (at + bits)
    }

    // Reads the header of one video packet, clause 6.2.5.2.
    mtd readPacketHeader(reader: *BitReader, header: *PlaneHeader, index: *u64) fail
    {
        let total = cast(u64) .layer.mbWidth * cast(u64) .layer.mbHeight
        var width = 1'u32
        while (1'u64 << width) < total and width < 14 do
            width += 1

        let number = cast(u64) reader.read(width)
        if number >= total do
            fail InvalidFormatError{"MPEG-4 video packet starts past the end of its plane"}
        index[] = number

        .quant = reader.read(.layer.quantPrecision)
        if !.quant do
            fail InvalidFormatError{"MPEG-4 video packet states a zero quantiser"}
        header.quant = .quant

        if reader.read(1) != 0
        {
            // The packet repeats enough of the plane header to stand on its own.
            var guard = 0'u32
            while reader.read(1) != 0
            {
                guard += 1
                if guard > 64 do
                    fail InvalidFormatError{"MPEG-4 video packet states an unbounded time base"}
            }

            reader.marker()
            discard reader.read(.layer.timeIncrementBits)
            reader.marker()
            header.codingType       = reader.read(2)
            header.intraDcThreshold = reader.read(3)
            if header.codingType != VopIntra do
                header.fcodeForward = reader.read(3)
            if header.codingType == VopBidirectional do
                header.fcodeBackward = reader.read(3)
        }
    }

    // Decodes one macroblock, clause 6.3.7.
    mtd decodeMacroblock(reader: *BitReader, header: const *PlaneHeader, mbX, mbY: s32) fail
    {
        let mbIndex = cast(u64) mbY * cast(u64) .layer.mbWidth + cast(u64) mbX
        let state   = &.macroblocks[mbIndex]
        state[] = MacroblockState{}

        if header.codingType == VopBidirectional
        {
            try .decodeBidirectionalMacroblock(reader, header, mbX, mbY)
            return
        }

        var coded = true
        if header.codingType == VopPredicted and reader.read(1) != 0 do
            coded = false

        if !coded
        {
            // A macroblock the plane did not code repeats what the reference holds, unmoved.
            .predictMacroblock(mbX, mbY, state, header.rounding)
            .clearBlockState(mbIndex)
            return
        }

        var mbType = TypeStuffing
        var cbpc   = 0'u32
        for 64'u32
        {
            let tree: const [..] s16   = header.codingType == VopIntra ? McbpcITree : McbpcPTree
            let types: const [..] u8   = header.codingType == VopIntra ? McbpcIType : McbpcPType
            let chroma: const [..] u8  = header.codingType == VopIntra ? McbpcICbpc : McbpcPCbpc
            let entry = reader.decode(tree)
            if entry < 0 do
                fail InvalidFormatError{"MPEG-4 macroblock states no coded block pattern"}
            mbType = cast(u32) types[cast(u64) entry]
            cbpc   = cast(u32) chroma[cast(u64) entry]
            if mbType != TypeStuffing do
                break
        }

        if mbType == TypeStuffing do
            fail InvalidFormatError{"MPEG-4 plane stuffs where a macroblock belongs"}

        let intra  = mbType == TypeIntra or mbType == TypeIntraQ
        var acPred = false
        if intra do
            acPred = reader.read(1) != 0

        let cbpyEntry = reader.decode(CbpyTree)
        if cbpyEntry < 0 do
            fail InvalidFormatError{"MPEG-4 macroblock states no luminance block pattern"}
        let cbpy = cast(u32) (intra ? CbpyIntra[cast(u64) cbpyEntry] : CbpyInter[cast(u64) cbpyEntry])

        if mbType == TypeInterQ or mbType == TypeIntraQ
        {
            let delta = cast(s32) DquantDelta[cast(u64) reader.read(2)]
            .quant = cast(u32) Math.clamp(cast(s32) .quant + delta, 1's32, 31's32)
        }

        state.intra = intra
        state.coded = true

        if !intra
        {
            let count = mbType == TypeInter4V ? 4'u64 : 1'u64
            for index in count
            {
                var vector: Vector
                let predicted = .predictVector(mbX, mbY, index, mbType == TypeInter4V)
                if !readVectorDelta(reader, header.fcodeForward, &vector) do
                    fail InvalidFormatError{"MPEG-4 macroblock states no motion vector"}
                state.vectors[index].x = wrapVector(predicted.x + vector.x, header.fcodeForward)
                state.vectors[index].y = wrapVector(predicted.y + vector.y, header.fcodeForward)
            }

            if count == 1
            {
                for index in 1 until 4'u64 do
                    state.vectors[index] = state.vectors[0]
            }

            .predictMacroblock(mbX, mbY, state, header.rounding)
        }

        // The six blocks, luminance first, in the order the pattern names them.
        let pattern = (cbpy << 2) | cbpc
        for block in 6'u64
        {
            let coded6 = (pattern & (32 >> block)) != 0
            try .decodeBlock(reader, header, mbX, mbY, block, intra, acPred, coded6)
        }

        if reader.overran() do
            fail InvalidFormatError{"MPEG-4 plane is truncated"}
    }

    // Decodes one macroblock of a bidirectional plane, clause 6.2.6.
    //
    // A bidirectional macroblock says which of its two references it uses, or says nothing at all
    // and takes the motion of the plane that follows it, scaled to where it sits between them.
    mtd decodeBidirectionalMacroblock(reader: *BitReader, header: const *PlaneHeader, mbX, mbY: s32) fail
    {
        let mbIndex = cast(u64) mbY * cast(u64) .layer.mbWidth + cast(u64) mbX
        let state   = &.macroblocks[mbIndex]
        state[] = MacroblockState{}
        .clearBlockState(mbIndex)

        var kind    = TypeDirect
        var pattern = 0'u32
        var delta:  Vector
        var mvForward:  Vector
        var mvBackward: Vector

        if reader.read(1) == 0
        {
            let hasPattern = reader.read(1) == 0

            // The type is a run of zeros closed by a one: 1, 01, 001, 0001.
            if reader.read(1) == 0
            {
                if reader.read(1) != 0 do
                    kind = TypeInterpolated
                elif reader.read(1) != 0 do
                    kind = TypeBackward
                else
                {
                    discard reader.read(1)
                    kind = TypeForward
                }
            }

            if hasPattern do
                pattern = reader.read(6)

            // The quantiser moves only when the macroblock carries something to quantise.
            if kind != TypeDirect and pattern and reader.read(1) != 0
            {
                let step = reader.read(1) != 0 ? 2's32 : -2's32
                .quant = cast(u32) Math.clamp(cast(s32) .quant + step, 1's32, 31's32)
            }

            if kind == TypeDirect
            {
                // The direct mode states one delta, read as though the code were one.
                if !readVectorDelta(reader, 1, &delta) do
                    fail InvalidFormatError{"MPEG-4 direct macroblock states no motion vector"}
            }
            else
            {
                // A bidirectional plane predicts each direction from the macroblock before it,
                // not from a median, clause 7.6.6.
                if kind == TypeForward or kind == TypeInterpolated
                {
                    var step: Vector
                    if !readVectorDelta(reader, header.fcodeForward, &step) do
                        fail InvalidFormatError{"MPEG-4 macroblock states no forward vector"}
                    .forward.x = wrapVector(.forward.x + step.x, header.fcodeForward)
                    .forward.y = wrapVector(.forward.y + step.y, header.fcodeForward)
                    mvForward  = .forward
                }

                if kind == TypeBackward or kind == TypeInterpolated
                {
                    var step: Vector
                    if !readVectorDelta(reader, header.fcodeBackward, &step) do
                        fail InvalidFormatError{"MPEG-4 macroblock states no backward vector"}
                    .backward.x = wrapVector(.backward.x + step.x, header.fcodeBackward)
                    .backward.y = wrapVector(.backward.y + step.y, header.fcodeBackward)
                    mvBackward  = .backward
                }
            }
        }

        if kind == TypeDirect do
            .predictDirect(mbX, mbY, delta, header.rounding)
        else do
            .predictBidirectional(mbX, mbY, kind, mvForward, mvBackward, header.rounding)

        // A bidirectional macroblock is never intra, so its blocks carry a residual or nothing.
        for block in 6'u64 where (pattern & (32 >> block)) != 0 do
            try .decodeBlock(reader, header, mbX, mbY, block, false, false, true)

        if reader.overran() do
            fail InvalidFormatError{"MPEG-4 plane is truncated"}
    }

    // Predicts one macroblock from one anchor or from both.
    mtd predictBidirectional(mbX, mbY: s32, kind: u32, mvForward, mvBackward: Vector, rounding: u32)
    {
        var vectors: [4] Vector = undefined
        if kind != TypeBackward
        {
            for index in 4'u64 do
                vectors[index] = mvForward
            .predictFrom(&.anchorOld, mbX, mbY, vectors, rounding, false)
        }

        if kind != TypeForward
        {
            for index in 4'u64 do
                vectors[index] = mvBackward
            .predictFrom(&.anchorNew, mbX, mbY, vectors, rounding, kind == TypeInterpolated)
        }
    }

    // Predicts one macroblock the way the plane that follows it moved, clause 7.6.7.
    mtd predictDirect(mbX, mbY: s32, delta: Vector, rounding: u32)
    {
        let mbIndex = cast(u64) mbY * cast(u64) .layer.mbWidth + cast(u64) mbX
        let source  = &.coLocated[mbIndex]
        let trd     = .newTime - .oldTime
        let trb     = .planeTime - .oldTime
        if trd <= 0 do
            return

        var forward:  [4] Vector = undefined
        var backward: [4] Vector = undefined
        for block in 4'u64
        {
            var mv: Vector
            if !source.intra do
                mv = source.vectors[block]
            forward[block].x  = cast(s32) ((trb * cast(s64) mv.x) / trd) + delta.x
            forward[block].y  = cast(s32) ((trb * cast(s64) mv.y) / trd) + delta.y
            backward[block].x = !delta.x ? cast(s32) (((trb - trd) * cast(s64) mv.x) / trd) : forward[block].x - mv.x
            backward[block].y = !delta.y ? cast(s32) (((trb - trd) * cast(s64) mv.y) / trd) : forward[block].y - mv.y
        }

        .predictFrom(&.anchorOld, mbX, mbY, forward, rounding, false)
        .predictFrom(&.anchorNew, mbX, mbY, backward, rounding, true)
    }

    // Fills one macroblock from one anchor, either outright or averaged into what is there.
    mtd predictFrom(anchor: *Frame, mbX, mbY: s32, vectors: [4] Vector, rounding: u32, average: bool)
    {
        let lumaAt   = anchor.lumaOrigin()
        let chromaAt = anchor.chromaOrigin()
        let x        = mbX * 16
        let y        = mbY * 16

        for block in 4'u64
        {
            let bx = x + cast(s32) (block & 1) * 8
            let by = y + cast(s32) (block >> 1) * 8
            let target = .current.lumaOrigin() + cast(u64) cast(s64) (cast(s64) by * cast(s64) .current.strideLuma + cast(s64) bx)
            if average
            {
                compensate(&.blend[0], 8, anchor.luma.buffer!, lumaAt, anchor.strideLuma,
                           bx, by, vectors[block], 8, 8, rounding, anchor.width, anchor.height)
                blendInto(.current.luma.buffer! + target, .current.strideLuma, &.blend[0], 8, 8, 8)
            }
            else
            {
                compensate(.current.luma.buffer! + target, .current.strideLuma,
                           anchor.luma.buffer!, lumaAt, anchor.strideLuma,
                           bx, by, vectors[block], 8, 8, rounding, anchor.width, anchor.height)
            }
        }

        let chroma = chromaVector(vectors)
        let cx     = mbX * 8
        let cy     = mbY * 8
        let target = .current.chromaOrigin() + cast(u64) cast(s64) (cast(s64) cy * cast(s64) .current.strideChroma + cast(s64) cx)
        for plane in 2'u32
        {
            let from = plane == 0 ? anchor.chromaB.buffer! : anchor.chromaR.buffer!
            let into = plane == 0 ? .current.chromaB.buffer! : .current.chromaR.buffer!
            if average
            {
                compensate(&.blend[0], 8, from, chromaAt, anchor.strideChroma, cx, cy, chroma, 8, 8, rounding, anchor.width / 2, anchor.height / 2)
                blendInto(into + target, .current.strideChroma, &.blend[0], 8, 8, 8)
            }
            else
            {
                compensate(into + target, .current.strideChroma, from, chromaAt, anchor.strideChroma,
                           cx, cy, chroma, 8, 8, rounding, anchor.width / 2, anchor.height / 2)
            }
        }
    }

    // Marks the six blocks of a macroblock as carrying no intra prediction.
    mtd clearBlockState(mbIndex: u64)
    {
        for block in 6'u64
        {
            let state = &.blocks[mbIndex * 6 + block]
            state[] = BlockState{}
            state.dc    = DefaultNeighbourDc
            state.quant = cast(u8) .quant
        }
    }

    // The vector a block is predicted with, clause 7.6.5.
    mtd const predictVector(mbX, mbY: s32, block: u64, fourVectors: bool)->Vector
    {
        // Which neighbouring block each of the three candidates comes from, figure 7-8.
        var candidates: [3] Vector = undefined
        var valid:      [3] bool   = undefined

        for slot in 3'u64
        {
            var nx    = mbX
            var ny    = mbY
            var which = 0'u64
            switch block
            {
            case 0:
                if !slot { nx -= 1; which = 1 } elif slot == 1 { ny -= 1; which = 2 } else { nx += 1; ny -= 1; which = 2 }
            case 1:
                if !slot { which = 0 } elif slot == 1 { ny -= 1; which = 3 } else { nx += 1; ny -= 1; which = 2 }
            case 2:
                if !slot { nx -= 1; which = 3 } elif slot == 1 { which = 0 } else { which = 1 }
            default:
                if !slot { which = 2 } elif slot == 1 { which = 0 } else { which = 1 }
            }

            // A candidate inside the current macroblock is always available; one outside the
            // picture, or in a macroblock that carries no vector, is not.
            if nx == mbX and ny == mbY
            {
                let state = &.macroblocks[cast(u64) mbY * cast(u64) .layer.mbWidth + cast(u64) mbX]
                candidates[slot] = state.vectors[fourVectors ? which : 0]
                valid[slot]      = true
                continue
            }

            valid[slot] = false
            if nx < 0 or ny < 0 or nx >= cast(s32) .layer.mbWidth or ny >= cast(s32) .layer.mbHeight do
                continue

            let neighbourIndex = cast(u64) ny * cast(u64) .layer.mbWidth + cast(u64) nx
            if neighbourIndex < .packetStart do
                continue

            let state = &.macroblocks[neighbourIndex]
            candidates[slot] = state.vectors[which]
            valid[slot]      = true
        }

        // Clause 7.6.5: one missing candidate reads as zero, two take the third, three are zero.
        var count = 0'u32
        for slot in 3'u64 where valid[slot] do
            count += 1

        if !count do
            return Vector{}
        if count == 1
        {
            for slot in 3'u64 where valid[slot] do
                return candidates[slot]
        }

        for slot in 3'u64 where !valid[slot] do
            candidates[slot] = Vector{}

        var result: retval
        result.x = median(candidates[0].x, candidates[1].x, candidates[2].x)
        result.y = median(candidates[0].y, candidates[1].y, candidates[2].y)
        return result
    }

    // Fills one macroblock of the current picture from the reference it points at.
    mtd predictMacroblock(mbX, mbY: s32, state: const *MacroblockState, rounding: u32)
    {
        if !.anchors do
            return

        let lumaAt   = .anchorNew.lumaOrigin()
        let chromaAt = .anchorNew.chromaOrigin()
        let x        = mbX * 16
        let y        = mbY * 16

        for block in 4'u64
        {
            let bx = x + cast(s32) (block & 1) * 8
            let by = y + cast(s32) (block >> 1) * 8
            let target = .current.lumaOrigin() + cast(u64) cast(s64) (cast(s64) by * cast(s64) .current.strideLuma + cast(s64) bx)
            compensate(.current.luma.buffer! + target, .current.strideLuma,
                       .anchorNew.luma.buffer!, lumaAt, .anchorNew.strideLuma,
                       bx, by, state.vectors[block], 8, 8, rounding, .anchorNew.width, .anchorNew.height)
        }

        var vectors: [4] Vector = state.vectors
        let chroma = chromaVector(vectors)
        let cx     = mbX * 8
        let cy     = mbY * 8
        let target = .current.chromaOrigin() + cast(u64) cast(s64) (cast(s64) cy * cast(s64) .current.strideChroma + cast(s64) cx)
        compensate(.current.chromaB.buffer! + target, .current.strideChroma,
                   .anchorNew.chromaB.buffer!, chromaAt, .anchorNew.strideChroma, cx, cy, chroma, 8, 8, rounding, .anchorNew.width / 2, .anchorNew.height / 2)
        compensate(.current.chromaR.buffer! + target, .current.strideChroma,
                   .anchorNew.chromaR.buffer!, chromaAt, .anchorNew.strideChroma, cx, cy, chroma, 8, 8, rounding, .anchorNew.width / 2, .anchorNew.height / 2)
    }

    // Decodes one block and writes its samples, clause 6.3.7.3.
    mtd decodeBlock(reader: *BitReader, header: const *PlaneHeader, mbX, mbY: s32,
                    block: u64, intra, acPred, coded: bool) fail
    {
        let mbIndex = cast(u64) mbY * cast(u64) .layer.mbWidth + cast(u64) mbX
        let isLuma  = block < 4
        var levels: [64] s32 = undefined
        for index in 64'u64 do
            levels[index] = 0

        var fromAbove = false
        var scaler    = 1'u32
        var left:  BlockState
        var above: BlockState

        if intra
        {
            // The three neighbours of figure 7-6, then the direction of clause 7.4.3.1.
            var corner: BlockState
            switch block
            {
            case 0:
                left = .neighbour(mbX - 1, mbY, 1); corner = .neighbour(mbX - 1, mbY - 1, 3); above = .neighbour(mbX, mbY - 1, 2)
            case 1:
                left = .blocks[mbIndex * 6 + 0]; corner = .neighbour(mbX, mbY - 1, 2); above = .neighbour(mbX, mbY - 1, 3)
            case 2:
                left = .neighbour(mbX - 1, mbY, 3); corner = .neighbour(mbX - 1, mbY, 1); above = .blocks[mbIndex * 6 + 0]
            case 3:
                left = .blocks[mbIndex * 6 + 2]; corner = .blocks[mbIndex * 6 + 0]; above = .blocks[mbIndex * 6 + 1]
            default:
                left = .neighbour(mbX - 1, mbY, block); corner = .neighbour(mbX - 1, mbY - 1, block); above = .neighbour(mbX, mbY - 1, block)
            }

            fromAbove = Math.abs(left.dc - corner.dc) < Math.abs(corner.dc - above.dc)
            scaler    = dcScaler(isLuma, .quant)

            // The direct current has its own code while the quantiser stays under the threshold
            // the plane states, clause 6.3.5.
            if usesDcCode(header.intraDcThreshold, .quant)
            {
                let tree: const [..] s16 = isLuma ? DcLumaTree : DcChromaTree
                let sizes: const [..] u8 = isLuma ? DcLumaSize : DcChromaSize
                let entry = reader.decode(tree)
                if entry < 0 do
                    fail InvalidFormatError{"MPEG-4 intra block states no direct-current width"}
                let size = cast(u32) sizes[cast(u64) entry]
                if size
                {
                    var value = cast(s32) reader.read(size)
                    if (value & (1's32 << (size - 1))) == 0 do
                        value -= (1's32 << size) - 1
                    if size > 8 do
                        reader.marker()
                    levels[0] = value
                }
            }
        }

        if coded
        {
            let scan: const [..] u8 = !intra or !acPred ? ScanZigzag
                                      : (fromAbove ? ScanAlternateHorizontal : ScanAlternateVertical)
            var at = intra and usesDcCode(header.intraDcThreshold, .quant) ? 1'u64 : 0'u64
            for 64'u32
            {
                var event: Coefficient
                if !readCoefficient(reader, !intra, &event) do
                    fail InvalidFormatError{"MPEG-4 block states an unknown coefficient"}
                at += cast(u64) event.run
                if at >= 64 do
                    fail InvalidFormatError{"MPEG-4 block codes more coefficients than a block holds"}
                levels[cast(u64) scan[at]] = event.level
                at += 1
                if event.last do
                    break
            }
        }

        if intra
        {
            // The direct current is predicted from a neighbour scaled to this block's step, and
            // the first row or column may be predicted too, clause 7.4.3.
            let predictor = fromAbove ? above.dc : left.dc
            levels[0] += divideRound(predictor, cast(s32) scaler)
            if acPred
            {
                if fromAbove
                {
                    for index in 7'u64 do
                        levels[index + 1] += divideRound(cast(s32) above.row[index] * cast(s32) above.quant, cast(s32) .quant)
                }
                else
                {
                    for index in 7'u64 do
                        levels[(index + 1) * 8] += divideRound(cast(s32) left.col[index] * cast(s32) left.quant, cast(s32) .quant)
                }
            }

            for index in 64'u64 do
                levels[index] = Math.clamp(levels[index], -2048's32, 2047's32)
        }

        // What this block leaves for the ones that predict from it.
        let state = &.blocks[mbIndex * 6 + block]
        state.intra = intra
        state.quant = cast(u8) .quant
        if intra
        {
            state.dc = levels[0] * cast(s32) scaler
            for index in 7'u64
            {
                state.row[index] = cast(s16) levels[index + 1]
                state.col[index] = cast(s16) levels[(index + 1) * 8]
            }
        }
        else
        {
            state.dc = DefaultNeighbourDc
            for index in 7'u64
            {
                state.row[index] = 0
                state.col[index] = 0
            }
        }

        if !coded and !intra do
            return

        if intra do
            levels[0] *= cast(s32) scaler
        dequantise(&levels, &.layer, .quant, intra, isLuma)

        var samples: [64] s16 = undefined
        inverseTransform(&levels, &samples)
        .writeBlock(mbX, mbY, block, &samples, intra)
    }

    // Writes one reconstructed block, either outright or on top of what motion left.
    mtd writeBlock(mbX, mbY: s32, block: u64, samples: const *[64] s16, intra: bool)
    {
        var plane  = .current.luma.buffer!
        var stride = .current.strideLuma
        var at     = .current.lumaOrigin()
        var x      = mbX * 16 + cast(s32) (block & 1) * 8
        var y      = mbY * 16 + cast(s32) (block >> 1) * 8

        if block >= 4
        {
            plane  = block == 4 ? .current.chromaB.buffer! : .current.chromaR.buffer!
            stride = .current.strideChroma
            at     = .current.chromaOrigin()
            x      = mbX * 8
            y      = mbY * 8
        }

        let origin = at + cast(u64) cast(s64) (cast(s64) y * cast(s64) stride + cast(s64) x)
        for row in 8'u64
        {
            let line = origin + row * stride
            for column in 8'u64
            {
                // Part 2 transforms the sample values themselves, with no level shift: what
                // comes out of an intra block is the sample, and the default neighbour of an
                // unpredicted block is mid grey by construction.
                let value = cast(s32) samples[][row * 8 + column]
                let final = intra ? value : cast(s32) plane[line + column] + value
                plane[line + column] = cast(u8) Math.clamp(final, 0's32, 255's32)
            }
        }
    }
}

// Whether the direct current of an intra block has its own code, Table 6-25.
func usesDcCode(threshold, quant: u32)->bool
{
    switch threshold
    {
    case 0:
        return true
    case 1:
        return quant < 13
    case 2:
        return quant < 15
    case 3:
        return quant < 17
    case 4:
        return quant < 19
    case 5:
        return quant < 21
    case 6:
        return quant < 23
    }

    return false
}

// The division of clause 4.1: to the nearest integer, halves away from zero.
func divideRound(value, by: s32)->s32
{
    if value >= 0 do
        return (value + by / 2) / by
    return -((-value + by / 2) / by)
}
