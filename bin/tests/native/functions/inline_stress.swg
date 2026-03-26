#global fileprivate

#[Swag.Inline]
func hasAnyAbove(arr: [*] u8, count: u32, limit: u8)->bool
{
    for i in count
    {
        if arr[i] > limit do return true
    }

    return false
}

#[Swag.Inline]
func firstAboveIndex(arr: [*] u8, count: u32, limit: u8)->s32
{
    for i in count
    {
        if arr[i] > limit do return cast(s32) i
    }

    return -1
}

func runInlineScanStress(arr: [*] u8, count: u32)->u32
{
    var limits: [4] u8 = [0, 4, 8, 9]
    var total: u32

    for i in 4
    {
        if hasAnyAbove(arr, count, limits[i])
            do total += 1

        let index = firstAboveIndex(arr, count, limits[i])
        if index >= 0
            do total += cast(u32) index
    }

    return total
}

#[Swag.Inline]
func addOne(value: s32)->s32
{
    return value + 1
}

#[Swag.Inline]
func double(value: s32)->s32
{
    return value * 2
}

#[Swag.Inline]
func bumpThenDouble(value: s32)->s32
{
    return double(addOne(value))
}

#[Swag.Inline]
func nestedChain(value: s32)->s32
{
    return double(addOne(double(addOne(value))))
}

func packPair(a: s32, b: s32)->s32
{
    return a * 100 + b
}

func runNestedInlineStress(count: u32)->s32
{
    var total: s32

    for i in count
    {
        total += bumpThenDouble(cast(s32) i)
    }

    return total
}

#test
{
    var data: [6] u8 = [1, 5, 3, 9, 2, 4]

    @assert(hasAnyAbove(&data[0], 6, 0))
    @assert(hasAnyAbove(&data[0], 6, 4))
    @assert(hasAnyAbove(&data[0], 6, 8))
    @assert(!hasAnyAbove(&data[0], 6, 9))

    @assert(firstAboveIndex(&data[0], 6, 0) == 0)
    @assert(firstAboveIndex(&data[0], 6, 4) == 1)
    @assert(firstAboveIndex(&data[0], 6, 8) == 3)
    @assert(firstAboveIndex(&data[0], 6, 9) == -1)

    // @BUG repeated inline loop scans do not preserve the expected aggregate result yet.
    // @assert(runInlineScanStress(&data[0], 6) == 7)
}

#test
{
    var value = 10

    @assert(bumpThenDouble(5) == 12)
    @assert(bumpThenDouble(value) == 22)
    @assert(nestedChain(5) == 26)
    @assert(nestedChain(value) == 46)
    @assert(double(addOne(double(addOne(5)))) == 26)
    @assert(packPair(bumpThenDouble(1), bumpThenDouble(value)) == 422)
    @assert(runNestedInlineStress(4) == 20)
}
