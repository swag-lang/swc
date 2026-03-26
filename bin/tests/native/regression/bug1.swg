#global fileprivate
#global skip

#[Swag.Inline]
func hasAnyAbove(arr: [*] u8, count: u32, limit: u8) -> bool
{
    for i in count
    {
        if arr[i] > limit do return true
    }
    return false
}

#test
{
    var data: [3] u8
    data[0] = 1; data[1] = 5; data[2] = 3

    // Should be true (data[1]=5 > 4), but inline return never fires
    @assert(hasAnyAbove(&data[0], 3, 4))
}