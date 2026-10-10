#global private

// A fast path that steps over a slow call returning a value: the call's result is copied out
// of the return register before the join. Values live across the call keep caller-saved
// registers on the fast path and are parked in the slow block, which must restore them.

var g_SlowCalls = 0'u64

#[Swag.NoInline]
func slowLookup(key: u64)->u64
{
    g_SlowCalls += 1
    return key * 3 + 1
}

#[Swag.Optimize(true), Swag.NoInline]
func lookup(table: [*] u64, key, bias, scale: u64)->u64
{
    var value = table[key & 7]
    if key >= 8 do
        value = slowLookup(key)
    return value * scale + bias + key
}

#test
{
    var table: [8] u64 = [10, 11, 12, 13, 14, 15, 16, 17]
    var sum   = 0'u64
    for key in 16'u64 do
        sum += lookup(&table[0], key, 5, 2)

    var expected = 0'u64
    for key in 16'u64
    {
        let value = key < 8 ? table[key] : key * 3 + 1
        expected += value * 2 + 5 + key
    }

    Swag.assert(sum == expected)
    Swag.assert(g_SlowCalls == 8)
}
