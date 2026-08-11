#global export
#global namespace Slice

// Find 'value' in a slice by performing a binary search.
// The slice must be sorted in ascending order
// Returns Swag.U64.Max if not found.
func(T, V) findSorted(values: #null const [..] T, value: V)->u64
{
    var lower = 0'u64
    var upper = @countof(values)
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
func(T, V) findLinear(values: #null const [..] T, value: V)->u64
{
    for v, i in values where v == value do
        return i
    return Swag.U64.Max
}

// Returns the first index of `subslice`, or `Swag.U64.Max` when it is absent.
func(T) findSubslice(values: const [..] T, subslice: const [..] T)->u64
{
    if !@countof(subslice) do
        return 0
    if @countof(subslice) > @countof(values) do
        return Swag.U64.Max

    for it0 in 0 to @countof(values) - @countof(subslice)
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
func(T, V) contains(values: #null const [..] T, value: V)->bool
{
    for v in values where v == value do
        return true
    return false
}

// Returns true if two slices are equal
#[Swag.ConstExpr]
func(T) equals(dst, src: #null const [..] T)->bool
{
    if @countof(dst) != @countof(src) do
        return false
    if !@countof(dst) or !@countof(src) do
        return true

    let dstn = dst!
    let srcn = src!
    for i in @countof(dstn) where dstn[i] != srcn[i] do
        return false
    return true
}
