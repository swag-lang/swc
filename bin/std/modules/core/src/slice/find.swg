#global export
#global namespace Slice

private func findByte(values: const [*] u8, count: u64, value: u8)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let needle = Math.Simd.splat(value)
    var offset = 0'u64
    while count - offset >= 4 * VectorSize
    {
        let matches0 = Math.Simd.bitmask(Math.Simd.load(values + offset) == needle)
        let matches1 = Math.Simd.bitmask(Math.Simd.load(values + offset + VectorSize) == needle)
        let matches2 = Math.Simd.bitmask(Math.Simd.load(values + offset + 2 * VectorSize) == needle)
        let matches3 = Math.Simd.bitmask(Math.Simd.load(values + offset + 3 * VectorSize) == needle)
        if matches0 do
            return offset + Math.trailingZeros(matches0)
        if matches1 do
            return offset + VectorSize + Math.trailingZeros(matches1)
        if matches2 do
            return offset + 2 * VectorSize + Math.trailingZeros(matches2)
        if matches3 do
            return offset + 3 * VectorSize + Math.trailingZeros(matches3)
        offset += 4 * VectorSize
    }

    while count - offset >= VectorSize
    {
        let matches = Math.Simd.bitmask(Math.Simd.load(values + offset) == needle)
        if matches do
            return offset + Math.trailingZeros(matches)
        offset += VectorSize
    }

    while offset < count
    {
        if values[offset] == value do
            return offset
        offset += 1
    }

    return Swag.U64.Max
}

#[Swag.Inline]
private func verifyByteCandidates(values, subslice: const [*] u8, subCount, baseOffset: u64, candidateMask: u32)->u64
{
    var mask = candidateMask
    while mask
    {
        let offset = baseOffset + Math.trailingZeros(mask)
        if Memory.compare(values + offset, subslice, subCount) == 0 do
            return offset
        mask &= mask - 1
    }

    return Swag.U64.Max
}

// Find 'value' in a slice by performing a binary search.
// The slice must be sorted in ascending order
// Returns Swag.U64.Max if not found.
func(T, V) findSorted(values: #null const [..] T, value: V)->u64
{
    var lower = 0'u64
    var upper = values.count
    if !upper do
        return Swag.U64.Max
    let vals = values!

    while lower < upper
    {
        let mid = lower + (upper - lower) / 2

        let res = vals[mid] <=> value
        if res == 0 do
            return mid
        if res < 0 do
            lower = mid + 1
        else do
            upper = mid
    }

    return Swag.U64.Max
}

// Find 'value' in a slice by performing a linear search.
// O^n, but slice does not have to be sorted.
// Returns Swag.U64.Max if not found.
func findLinear(values: #null const [..] u8, value: u8)->u64
{
    let count = values.count
    if !count do
        return Swag.U64.Max
    return findByte((values!).buffer, count, value)
}

func(T, V) findLinear(values: #null const [..] T, value: V)->u64
{
    for &v, i in values where v[] == value do
        return i
    return Swag.U64.Max
}

// Returns the first index of `subslice`, or `Swag.U64.Max` when it is absent.
func findSubslice(values, subslice: const [..] u8)->u64
{
    let valueCount = values.count
    let subCount   = subslice.count
    if !subCount do
        return 0
    if subCount > valueCount do
        return Swag.U64.Max

    let valueData      = values.buffer
    let subData        = subslice.buffer
    let lastStart      = valueCount - subCount
    let candidateCount = lastStart + 1
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let needle = Math.Simd.splat(subData[0])
    var offset = 0'u64
    while offset <= lastStart
    {
        let relative = findByte(valueData + offset, candidateCount - offset, subData[0])
        if relative == Swag.U64.Max do
            return Swag.U64.Max
        offset += relative
        if candidateCount - offset >= VectorSize
        {
            let mask   = Math.Simd.bitmask(Math.Simd.load(valueData + offset) == needle)
            let result = verifyByteCandidates(valueData, subData, subCount, offset, mask)
            if result != Swag.U64.Max do
                return result
            offset += VectorSize
            continue
        }

        while offset <= lastStart
        {
            if valueData[offset] == subData[0] and Memory.compare(valueData + offset, subData, subCount) == 0 do
                return offset
            offset += 1
        }
    }

    return Swag.U64.Max
}

func(T) findSubslice(values: const [..] T, subslice: const [..] T)->u64
{
    if !subslice.count do
        return 0
    if subslice.count > values.count do
        return Swag.U64.Max

    for it0 in 0 to values.count - subslice.count
    {
        var ok = true
        for item, it1 in subslice
        {
            if values[it0 + it1] != item
            {
                ok = false
                break
            }
        }

        if ok do
            return it0
    }

    return Swag.U64.Max
}

// Returns true if the given slice contains the 'value'.
// The slice must be sorted in ascending order
#[Swag.ConstExpr]
func(T, V) containsSorted(values: #null const [..] T, value: V)->bool
{
    return findSorted(values, value) != Swag.U64.Max
}

// Returns true if the given slice contains the 'value'
#[Swag.ConstExpr]
func contains(values: #null const [..] u8, value: u8)->bool
{
    return findLinear(values, value) != Swag.U64.Max
}

#[Swag.ConstExpr]
func(T, V) contains(values: #null const [..] T, value: V)->bool
{
    for v in values where v == value do
        return true
    return false
}

// Returns true if two slices are equal
#[Swag.ConstExpr]
func equals(dst, src: #null const [..] u8)->bool
{
    if dst.count != src.count do
        return false
    if !dst.count do
        return true
    return Memory.compare((dst!).buffer, (src!).buffer, dst.count) == 0
}

#[Swag.ConstExpr]
func(T) equals(dst, src: #null const [..] T)->bool
{
    if dst.count != src.count do
        return false
    if !dst.count or !src.count do
        return true

    let dstn = dst!
    let srcn = src!
    for i in dstn.count where dstn[i] != srcn[i] do
        return false
    return true
}
