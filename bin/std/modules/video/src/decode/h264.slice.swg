#global namespace H264
#global internal

using Core, Core.Errors

// Slice coding types, after folding the redundant 5..9 range onto 0..4.
const SliceTypeP = 0'u32
const SliceTypeB = 1'u32
const SliceTypeI = 2'u32

// Everything a slice header declares, before reference lists are resolved.
struct SliceHeader
{
    firstMb:           u32
    type:              u32
    allSameType:       bool     // The in-stream type promised every slice of the picture is alike.
    ppsId:             u32
    frameNum:          u32
    isIdr:             bool
    pocLsb:            u32
    deltaPocBottom:    s32
    deltaPoc0:         s32
    deltaPoc1:         s32
    directSpatial:     bool
    refCount:          [2] u32
    cabacInitIdc:      u32
    qp:                s32
    deblockIdc:        u32
    alphaOffset:       s32
    betaOffset:        s32
}

// One resolved reference picture of a slice, with its explicit prediction weights.
struct RefPic
{
    frame:      #null *Frame
    poc:        s32
    isLong:     bool
    lumaWeight: s32
    lumaOffset: s32
    cbWeight:   s32
    cbOffset:   s32
    crWeight:   s32
    crOffset:   s32
}

// One reference-list modification operation of a slice header.
private struct ListOp
{
    kind:  u32
    value: u32
}

// One slice being decoded: its header, entropy state, and resolved reference lists.
struct Slice
{
    dec:            #null *Decoder
    header:         SliceHeader
    bits:           BitReader          // CAVLC entropy source, shared with the header.
    cabac:          CabacReader
    isCabac:        bool

    refs:           [2, 32] RefPic
    refCount:       [2] u32
    listOps:        [2] Array'ListOp   // Reference-list modifications, applied when lists build.
    lumaLog2Denom:  u32
    chromaLog2Denom: u32
    useWeights:     bool               // Explicit weights apply to every prediction.
    useImplicit:    bool               // Implicit weights apply to bidirectional predictions.
    implicitW1:     [32, 32] s16       // Implicit weight of the list-1 side, per reference pair.

    qp:             s32                // Current luma QP, carried from macroblock to macroblock.
    lastQpDelta:    s32                // For the CABAC QP-delta context.
    mbX:            s32
    mbY:            s32
    mbAddr:         u32
    sliceId:        u16
}

impl Slice
{
    // Reads one slice header, section 7.3.3, leaving the reader on the slice data.
    //
    // Returns false for a redundant slice, which a decoder ignores entirely.
    mtd parseHeader(dec: *Decoder, refIdc: u32, isIdr: bool)->bool fail
    {
        .dec = dec
        .bits.init(dec.rbsp.toSlice())

        .header.isIdr   = isIdr
        .header.firstMb = .bits.ue()
        let rawType     = .bits.ue()
        if rawType > 9 do
            fail InvalidFormatError{"H.264 slice declares an unknown slice type"}
        .header.allSameType = rawType >= 5
        .header.type        = rawType % 5
        if .header.type > SliceTypeI do
            fail UnsupportedFormatError{"video decoder does not support H.264 SP and SI slices"}
        if .header.type != SliceTypeI and isIdr do
            fail InvalidFormatError{"H.264 IDR picture carries a predicted slice"}

        .header.ppsId = .bits.ue()
        if .header.ppsId >= dec.ppsSet.count or !dec.ppsSet[.header.ppsId].valid do
            fail InvalidFormatError{"H.264 slice references an unknown picture parameter set"}
        let pps = &dec.ppsSet[.header.ppsId]
        let sps = &dec.spsSet[pps.spsId]
        dec.pps = pps
        dec.sps = sps

        .header.frameNum = .bits.read(sps.log2MaxFrameNum)

        if isIdr do
            discard .bits.ue()                   // idr_pic_id.

        if sps.pocType == 0
        {
            .header.pocLsb = .bits.read(sps.log2MaxPocLsb)
            if pps.picOrderPresent do
                .header.deltaPocBottom = .bits.se()
        }
        elif sps.pocType == 1 and !sps.deltaPocAlwaysZero
        {
            .header.deltaPoc0 = .bits.se()
            if pps.picOrderPresent do
                .header.deltaPoc1 = .bits.se()
        }

        if pps.redundantPicCntPresent
        {
            if .bits.ue() > 0 do
                return false
        }

        if .header.type == SliceTypeB do
            .header.directSpatial = .bits.bit() != 0

        .header.refCount[0] = pps.defaultRefCount[0]
        .header.refCount[1] = pps.defaultRefCount[1]
        if .header.type != SliceTypeI
        {
            if .bits.bit()
            {
                .header.refCount[0] = .bits.ue() + 1
                if .header.type == SliceTypeB do
                    .header.refCount[1] = .bits.ue() + 1
            }

            if .header.refCount[0] > 32 or .header.refCount[1] > 32 do
                fail InvalidFormatError{"H.264 slice declares an out-of-range reference count"}
        }

        // Reference list modifications are parsed now and applied while building the lists.
        for list in 2
        {
            if .header.type == SliceTypeI or (list == 1 and .header.type != SliceTypeB) do
                continue
            if !.bits.bit() do
                continue
            while true
            {
                let kind = .bits.ue()
                if kind == 3 do
                    break
                if kind > 2 do
                    fail InvalidFormatError{"H.264 slice carries an unknown reference-list modification"}
                .listOps[list].add({kind, .bits.ue()})
                if .listOps[list].count > 64 do
                    fail InvalidFormatError{"H.264 slice carries more list modifications than references"}
            }
        }

        // Explicit prediction weights sit here in the header; the lists themselves resolve
        // only once the picture is known, in [[buildLists]].
        .lumaLog2Denom   = 0
        .chromaLog2Denom = 0
        .useWeights      = false
        .useImplicit     = false
        .initDefaultWeights()
        let explicitWeights = (.header.type == SliceTypeP and pps.weightedPred) or (.header.type == SliceTypeB and pps.weightedBipredIdc == 1)
        if explicitWeights
        {
            .useWeights      = true
            .lumaLog2Denom   = .bits.ue()
            .chromaLog2Denom = .bits.ue()
            if .lumaLog2Denom > 7 or .chromaLog2Denom > 7 do
                fail InvalidFormatError{"H.264 slice declares an out-of-range weight denominator"}
            .initDefaultWeights()
            .parseWeights()
        }
        elif .header.type == SliceTypeB and pps.weightedBipredIdc == 2
        {
            .useImplicit = true
        }

        // Reference marking, kept for the end of the picture; every slice repeats it.
        if refIdc != 0 and !dec.markingParsed
        {
            dec.markingParsed   = true
            dec.adaptiveMarking = false
            dec.idrLongTerm     = false
            if isIdr
            {
                discard .bits.bit()              // no_output_of_prior_pics_flag.
                dec.idrLongTerm = .bits.bit() != 0
            }
            elif .bits.bit()
            {
                dec.adaptiveMarking = true
                while true
                {
                    let op = .bits.ue()
                    if op == 0 do
                        break
                    if op > 6 do
                        fail InvalidFormatError{"H.264 slice carries an unknown reference marking operation"}
                    var operation: MmcoOp
                    operation.op = op
                    if op == 1 or op == 3 do
                        operation.arg0 = .bits.ue()
                    if op == 2 do
                        operation.arg0 = .bits.ue()
                    if op == 3 do
                        operation.arg1 = .bits.ue()
                    if op == 4 or op == 6 do
                        operation.arg0 = .bits.ue()
                    dec.mmcoOps.add(operation)
                    if dec.mmcoOps.count > 64 do
                        fail InvalidFormatError{"H.264 slice carries more marking operations than references"}
                }
            }
        }
        elif refIdc != 0 and isIdr
        {
            .bits.skip(2)
        }
        elif refIdc != 0
        {
            // Later slices repeat the marking of the first; skip it without storing.
            if .bits.bit() do
                .skipRepeatedMarking()
        }

        if pps.cabac and .header.type != SliceTypeI do
            .header.cabacInitIdc = .bits.ue()
        if .header.cabacInitIdc > 2 do
            fail InvalidFormatError{"H.264 slice declares an unknown CABAC initialization"}

        .header.qp = pps.initQp + .bits.se()
        if .header.qp < 0 or .header.qp > 51 do
            fail InvalidFormatError{"H.264 slice declares an out-of-range QP"}

        if pps.deblockControlPresent
        {
            .header.deblockIdc = .bits.ue()
            if .header.deblockIdc > 2 do
                fail InvalidFormatError{"H.264 slice declares an unknown deblocking mode"}
            if .header.deblockIdc != 1
            {
                .header.alphaOffset = .bits.se() * 2
                .header.betaOffset  = .bits.se() * 2
            }
        }

        if .bits.overran do
            fail InvalidFormatError{"H.264 slice header is truncated"}

        .isCabac = pps.cabac
        .qp      = .header.qp
        return true
    }

    // Fills the default explicit weights of every possible reference entry.
    private mtd initDefaultWeights()
    {
        for list in 2'u64
        {
            for index in 32'u64
            {
                let entry = &.refs[list, index]
                entry.lumaWeight = 1's32 << .lumaLog2Denom
                entry.lumaOffset = 0
                entry.cbWeight   = 1's32 << .chromaLog2Denom
                entry.cbOffset   = 0
                entry.crWeight   = entry.cbWeight
                entry.crOffset   = 0
            }
        }
    }

    // Skips the adaptive marking operations repeated by a later slice of the same picture.
    private mtd skipRepeatedMarking()
    {
        while true
        {
            let op = .bits.ue()
            if op == 0 or .bits.overran do
                break
            if op == 1 or op == 2 or op == 4 or op == 6 do
                discard .bits.ue()
            elif op == 3
            {
                discard .bits.ue()
                discard .bits.ue()
            }
        }
    }

    // Builds both reference lists, section 8.2.4, once the current picture exists.
    mtd buildLists() fail
    {
        let dec         = .dec!
        let current     = dec.current!
        let maxFrameNum = 1's32 << dec.sps!.log2MaxFrameNum

        // Picture numbers of the short-term references, relative to this slice.
        for reference in dec.shortRefs
        {
            reference.frameNumWrap = cast(s32) reference.frameNum > cast(s32) .header.frameNum ? cast(s32) reference.frameNum - maxFrameNum : cast(s32) reference.frameNum
            reference.picNum       = reference.frameNumWrap
        }

        var initial: [2] Array'*Frame
        if .header.type == SliceTypeP
        {
            for reference in dec.shortRefs do
                initial[0].add(reference)
            Slice.sortByPicNumDescending(&initial[0])
        }
        else
        {
            // List 0: past pictures by descending order count, then future ones ascending.
            for reference in dec.shortRefs do
                initial[0].add(reference)
            Slice.sortForB(&initial[0], current.poc, false)
            for reference in dec.shortRefs do
                initial[1].add(reference)
            Slice.sortForB(&initial[1], current.poc, true)
        }

        for list in 2'u64
        {
            if list == 1 and .header.type != SliceTypeB do
                break
            for reference in dec.longRefs do
                initial[list].add(reference)
        }

        // Two identical bidirectional lists swap their first two entries.
        if .header.type == SliceTypeB and initial[1].count > 1 and Slice.sameList(initial[0], initial[1])
        {
            let first = initial[1][0]
            initial[1][0] = initial[1][1]
            initial[1][1] = first
        }

        for list in 2'u64
        {
            if list == 1 and .header.type != SliceTypeB do
                break
            .applyListOps(&initial[list], .listOps[list], cast(u32) list)

            let wanted = .header.refCount[list]
            if !initial[list].count do
                fail InvalidFormatError{"H.264 predicted slice has no reference picture"}
            .refCount[list] = wanted
            for index in wanted
            {
                let frame = initial[list][Math.min(cast(u64) index, initial[list].count - 1)]
                let entry = &.refs[list, index]
                entry.frame  = frame
                entry.poc    = frame.poc
                entry.isLong = frame.isLongTerm
            }
        }

        if .useImplicit do
            .buildImplicitWeights()
    }

    // Parses the explicit prediction weights of both lists.
    private mtd parseWeights() fail
    {
        let listCount = .header.type == SliceTypeB ? 2 : 1
        for list in listCount
        {
            for index in .header.refCount[list]
            {
                let entry = &.refs[list, index]
                if .bits.bit()
                {
                    entry.lumaWeight = .bits.se()
                    entry.lumaOffset = .bits.se()
                    if entry.lumaWeight < -128 or entry.lumaWeight > 127 or entry.lumaOffset < -128 or entry.lumaOffset > 127 do
                        fail InvalidFormatError{"H.264 slice declares an out-of-range luma weight"}
                }

                if .bits.bit()
                {
                    entry.cbWeight = .bits.se()
                    entry.cbOffset = .bits.se()
                    entry.crWeight = .bits.se()
                    entry.crOffset = .bits.se()
                    if entry.cbWeight < -128 or entry.cbWeight > 127 or entry.crWeight < -128 or entry.crWeight > 127 do
                        fail InvalidFormatError{"H.264 slice declares an out-of-range chroma weight"}
                }
            }
        }

        if .bits.overran do
            fail InvalidFormatError{"H.264 slice header is truncated"}
    }

    // Builds the implicit bidirectional weights, section 8.4.2.3.2.
    private mtd buildImplicitWeights()
    {
        let currentPoc = .dec!.current!.poc
        for index0 in .refCount[0]
        {
            for index1 in .refCount[1]
            {
                let ref0 = .refs[0, index0]
                let ref1 = .refs[1, index1]
                var weight1 = 32's32
                if !ref0.isLong and !ref1.isLong and ref0.poc != ref1.poc
                {
                    let tb = Math.clamp(currentPoc - ref0.poc, -128, 127)
                    let td = Math.clamp(ref1.poc - ref0.poc, -128, 127)
                    let tx = (16384 + Math.abs(td / 2)) / td
                    let scale = Math.clamp((tb * tx + 32) >> 6, -1024, 1023)
                    if (scale >> 2) >= -64 and (scale >> 2) <= 128 do
                        weight1 = scale >> 2
                }

                .implicitW1[index0, index1] = cast(s16) weight1
            }
        }
    }

    // Applies the reference-list modification operations, section 8.2.4.3.
    private mtd applyListOps(list: *Array'*Frame, ops: Array'ListOp, listIndex: u32) fail
    {
        if !ops.count do
            return

        let dec         = .dec!
        let maxFrameNum = 1's32 << dec.sps!.log2MaxFrameNum
        let wanted      = .header.refCount[listIndex]

        // The list is modified at its declared size; extend with repeats before inserting.
        while list.count < cast(u64) wanted and list.count do
            list.add(list.back())

        var insertPos  = 0'u64
        var picNumPred = cast(s32) .header.frameNum
        for operation in ops
        {
            var target: #null *Frame
            if operation.kind == 2
            {
                for reference in dec.longRefs where reference.longTermIdx == cast(s32) operation.value
                {
                    target = reference
                    break
                }
            }
            else
            {
                let delta = cast(s32) operation.value + 1
                var picNum = operation.kind == 0 ? picNumPred - delta : picNumPred + delta
                if picNum < 0 do
                    picNum += maxFrameNum
                elif picNum >= maxFrameNum do
                    picNum -= maxFrameNum
                picNumPred = picNum
                let wrapped = picNum > cast(s32) .header.frameNum ? picNum - maxFrameNum : picNum
                for reference in dec.shortRefs where reference.picNum == wrapped
                {
                    target = reference
                    break
                }
            }

            if !target do
                fail InvalidFormatError{"H.264 slice reorders a reference picture that does not exist"}

            // Insert at the running position, then drop the duplicate further down.
            let frame = target!
            list.insertAt(insertPos, frame)
            insertPos += 1
            var scan = insertPos
            while scan < list.count
            {
                if list[scan] == frame
                {
                    list.removeAtOrdered(scan)
                    break
                }

                scan += 1
            }
        }
    }

    // Sorts short-term references by descending picture number, for P lists.
    private func sortByPicNumDescending(list: *Array'*Frame)
    {
        for outer in list.count
        {
            for inner in outer + 1 until list.count
            {
                if list[inner].picNum > list[outer].picNum
                {
                    let swap = list[outer]
                    list[outer] = list[inner]
                    list[inner] = swap
                }
            }
        }
    }

    // Sorts short-term references for a B list: past then future for list 0, the reverse for
    // list 1, each side ordered outward from the current picture.
    private func sortForB(list: *Array'*Frame, currentPoc: s32, list1: bool)
    {
        for outer in list.count
        {
            for inner in outer + 1 until list.count
            {
                if Slice.bBefore(list[inner], list[outer], currentPoc, list1)
                {
                    let swap = list[outer]
                    list[outer] = list[inner]
                    list[inner] = swap
                }
            }
        }
    }

    // Reports whether `a` precedes `b` in a B reference list.
    private func bBefore(a, b: *Frame, currentPoc: s32, list1: bool)->bool
    {
        let aPast = a.poc <= currentPoc
        let bPast = b.poc <= currentPoc
        if aPast != bPast do
            return list1 ? !aPast : aPast
        if aPast do
            return a.poc > b.poc
        return a.poc < b.poc
    }

    // Reports whether both initial lists hold the same pictures in the same order.
    private func sameList(a, b: Array'*Frame)->bool
    {
        if a.count != b.count do
            return false
        for index in a.count where a[index] != b[index] do
            return false
        return true
    }
}
