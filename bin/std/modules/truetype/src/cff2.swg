using Swag, Core

const MaxCff2CharstringStack = 513_u32

struct Cff2VariationData
{
    indices: const [..] u8 = ""
    hasDefaultDeltas: bool
}

struct Cff2VariationStore
{
    activeRegions: Array!{bool}
    data: Array!{Cff2VariationData}
}

func cff2UInt(value: f64)->u32 fail
{
    if not Math.isFinite(value) or value < 0.0 or value > Swag.U32.Max or Math.floor(value) != value
    {
        try fault(0x08)
    }

    return cast(u32, value)
}

// Replaces the trailing defaults and deltas with their evaluated values. Each
// default is followed, in the delta section, by one delta per selected region.
func blendCff2Operands(store: const *Cff2VariationStore, vsIndex: u32, stack: [..] f64)->u64 fail
{
    if not stack.count or vsIndex >= store.data.count
    {
        try fault(0x08)
    }

    let blendCount   = try cff2UInt(stack[stack.count - 1])
    let data         = &store.data[vsIndex]
    let regionCount  = data.indices.count / 2
    let operandCount = cast(u64, blendCount) * (regionCount + 1)
    if not blendCount or operandCount >= stack.count
    {
        try fault(0x08)
    }

    let first = stack.count - operandCount - 1
    let end   = first + blendCount
    if data.hasDefaultDeltas
    {
        var delta = end
        for index in first until end
        {
            for region in regionCount
            {
                let ordinal = readPackedOffset(data.indices.buffer + region * 2, 2)
                if store.activeRegions[ordinal]
                {
                    stack[index] += stack[delta + region]
                }
            }

            delta += regionCount
        }
    }

    return end
}

// A region at normalized zero either contributes its full delta or is inactive.
// An axis with a zero peak, an unordered triple or support on both sides of
// zero is nonparticipating under the OpenType variation scalar rules.
private func regionAtDefault(region: const [..] u8, axisCount: u32)->bool fail
{
    var active = true
    for axis in axisCount
    {
        let offset = cast(u64, axis) * 6
        let start  = peekS16(region, offset)
        let peak   = peekS16(region, offset + 2)
        let end    = peekS16(region, offset + 4)
        if Math.abs(cast(s32, start)) > 16_384 or
           Math.abs(cast(s32, peak)) > 16_384 or
           Math.abs(cast(s32, end)) > 16_384
        {
            try fault(0x08)
        }

        if peak and start <= peak and peak <= end and (start >= 0 or end <= 0)
        {
            active = false
        }
    }

    return active
}

private struct Cff2VariationLocation
{
    offset: u32
    index:  u32
}

// CFF2 stores region lists and their indices in the OpenType Item Variation
// Store layout. Its deltas live in the charstrings, so each item count is zero.
#[Swag.Propagate]
func readCff2VariationStore(block: const [..] u8, offset: u64)->Cff2VariationStore fail
{
    let encodedSize = readU16(block, offset)
    let start       = offset + 2
    let size        = encodedSize == Swag.U16.Max ? block.count - start : cast(u64, encodedSize)
    let store       = getSlice(block, start, size)
    if readU16(store, 0) != 1
    {
        fault(0x08)
    }

    let regionOffset = cast(u64, readU32(store, 2))
    let dataCount    = readU16(store, 6)
    let headerSize   = 8_u64 + cast(u64, dataCount) * 4
    assertRange(store, 0, headerSize)
    if regionOffset < headerSize
    {
        fault(0x08)
    }

    let axisCount   = readU16(store, regionOffset)
    let regionCount = readU16(store, regionOffset + 2)
    let regionSize  = cast(u64, axisCount) * 6
    let regions     = getSlice(store, regionOffset + 4, cast(u64, regionCount) * regionSize)
    var result: #returntype
    result.activeRegions.reserve(regionCount)
    for index in regionCount
    {
        let position = cast(u64, index) * regionSize
        result.activeRegions.add(regionAtDefault(regions[position until position + regionSize], axisCount))
    }

    var locations: Array!{Cff2VariationLocation}
    locations.reserve(dataCount)
    for index in dataCount
    {
        let position = readU32(store, 8 + cast(u64, index) * 4)
        if position < headerSize
        {
            fault(0x08)
        }

        locations.add({position, cast(u32, index)})
    }

    // An offset can be shared by several vsindex values. Visit each physical
    // record once and reject partially overlapping records.
    locations.sort(func(a, b) => a.offset <=> b.offset)
    result.data.resize(dataCount)
    let regionEnd = regionOffset + 4 + regions.count
    var previousOffset, previousEnd: u64
    var previous: Cff2VariationData
    for location in locations
    {
        let dataOffset = cast(u64, location.offset)
        if dataOffset == previousOffset
        {
            result.data[location.index] = previous
            continue
        }

        if dataOffset < previousEnd or
           readU16(store, dataOffset) != 0 or
           readU16(store, dataOffset + 2) != 0
        {
            fault(0x08)
        }

        let count   = readU16(store, dataOffset + 4)
        let indices = getSlice(store, dataOffset + 6, cast(u64, count) * 2)
        let dataEnd = dataOffset + 6 + indices.count
        if dataOffset < regionEnd and dataEnd > regionOffset
        {
            fault(0x08)
        }

        var hasDefaultDeltas = false
        for region in count
        {
            let ordinal = peekU16(indices, cast(u64, region) * 2)
            if ordinal >= regionCount
            {
                fault(0x08)
            }

            hasDefaultDeltas = hasDefaultDeltas or result.activeRegions[ordinal]
        }

        previous       = {indices, hasDefaultDeltas}
        previousOffset = dataOffset
        previousEnd    = dataEnd
        result.data[location.index] = previous
    }

    return result
}

// Format 4 extends FDSelect format 3 with wider glyph and dictionary indices.
#[Swag.Propagate]
func readCff2FdSelect(font: const *CffFont, offset: u64)->const [..] u8 fail
{
    let glyphCount = font.charStrings.count()
    let count      = readU32(font.block, offset + 1)
    if not count or count > glyphCount
    {
        fault(0x08)
    }

    let table = getSlice(font.block, offset, 9_u64 + cast(u64, count) * 6)
    var range = table.buffer + 5
    var start = readPackedOffset(range, 4)
    if start
    {
        fault(0x08)
    }

    for count
    {
        let end = readPackedOffset(range + 6, 4)
        if end <= start or end > glyphCount or readPackedOffset(range + 4, 2) >= font.fdPrivate.count
        {
            fault(0x08)
        }

        start = end
        range += 6
    }

    if start != glyphCount
    {
        fault(0x08)
    }

    return table
}

#[Swag.Propagate]
func parseCff2Font(block: const [..] u8)->CffFont fail
{
    if readU16(block, 0) != 0x0200
    {
        fault(0x07)
    }

    let headerSize = cast(u64, readU8(block, 2))
    let topSize    = cast(u64, readU16(block, 3))
    if headerSize < 5 or not topSize
    {
        fault(0x08)
    }

    var result: #returntype
    result.block  = block
    result.isCff2 = true

    var top: CffDict
    top.decodeEntries!{true}(getSlice(block, headerSize, topSize))
    result.globalSubrs = readCffIndexWithCount!{4}(block, headerSize + topSize)
    let glyphOffset = cff2UInt(top.value(CFF_OP_CHARSTRINGS, 0, 0))
    let fdOffset    = cff2UInt(top.value(CFF_OP_FD_ARRAY, 0, 0))
    let vsOffset    = cff2UInt(top.value(CFF2_OP_VAR_STORE, 0, 0))
    let select      = cff2UInt(top.value(CFF_OP_FD_SELECT, 0, 0))
    let dataStart   = result.globalSubrs.end
    if glyphOffset < dataStart or
       fdOffset < dataStart or
       (vsOffset and vsOffset < dataStart) or
       (select and select < dataStart)
    {
        fault(0x08)
    }

    if top.has(CFF_OP_FONT_MATRIX)
    {
        let scale = top.value(CFF_OP_FONT_MATRIX, 0, 0)
        if scale <= 0 or
           top.value(CFF_OP_FONT_MATRIX, 3, 0) != scale or
           top.value(CFF_OP_FONT_MATRIX, 1, 1) or
           top.value(CFF_OP_FONT_MATRIX, 2, 1) or
           top.value(CFF_OP_FONT_MATRIX, 4, 1) or
           top.value(CFF_OP_FONT_MATRIX, 5, 1)
        {
            fault(0x07)
        }

        result.matrixScale = scale
    }

    result.charStrings = readCffIndexWithCount!{4}(block, glyphOffset)
    let fdArray = readCffIndexWithCount!{4}(block, fdOffset)
    if not result.charStrings.count() or
       result.charStrings.count() > Swag.U16.Max or
       not fdArray.count() or
       fdArray.count() > Swag.U16.Max + 1_u32 or
       (fdArray.count() != 1 and not select)
    {
        fault(0x08)
    }

    if vsOffset
    {
        result.variations = readCff2VariationStore(block, vsOffset)
    }

    result.fdPrivate.reserve(fdArray.count())
    var fd, privateDict: CffDict
    for index in fdArray.count()
    {
        fd.decodeEntries!{true}(fdArray.item(index))
        if fd.has(CFF_OP_FONT_MATRIX)
        {
            fault(0x07)
        }

        let length   = cff2UInt(fd.value(CFF_OP_PRIVATE, 0, 0))
        let position = cff2UInt(fd.value(CFF_OP_PRIVATE, 1, 0))
        if length and position < dataStart
        {
            fault(0x08)
        }

        var privateData: CffPrivate
        if length
        {
            privateDict.decodeEntries!{true}(getSlice(block, position, length), &result.variations)
            privateData.vsIndex = cff2UInt(privateDict.value(CFF2_OP_VSINDEX, 0, 0))
            let subrs = cff2UInt(privateDict.value(CFF_OP_SUBRS, 0, 0))
            if subrs
            {
                if subrs < length
                {
                    fault(0x08)
                }

                privateData.subrs = readCffIndexWithCount!{4}(block, cast(u64, position) + subrs)
            }
        }

        result.fdPrivate.add(privateData)
    }

    if select
    {
        result.fdSelect = readCffFdSelect(&result, select)
    }

    return result
}
