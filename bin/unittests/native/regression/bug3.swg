#global fileprivate

#[Swag.Inline]
func pickAbove(arr: [*] u8, count: u32, limit: u8)->s32
{
    for i in count
    {
        if arr[i] > limit do return cast(s32) i
    }

    return -1
}

func runInlineCaptureBug(arr: [*] u8, count: u32)->s32
{
    var limits: [3] u8 = [0, 4, 8]
    var total: s32

    for i in 3
    {
        total += pickAbove(arr, count, limits[i])
    }

    return total
}

#test
{
    var data: [4] u8 = [1, 5, 3, 9]
    @assert(runInlineCaptureBug(&data[0], 4) == 4)
}
