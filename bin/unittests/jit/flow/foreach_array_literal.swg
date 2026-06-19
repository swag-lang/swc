#global fileprivate

#test
{
    var total = 0
    foreach slope, idx in [{1, 1}, {3, 1}, {5, 1}] do
        total += slope.item0 * 10 + slope.item1 + cast(s32) idx

    @assert(total == 96)
}
