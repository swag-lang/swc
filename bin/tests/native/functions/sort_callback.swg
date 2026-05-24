#global fileprivate

struct SortNamedItem
{
    rank:  u64
    total: s64
}

func(T) pickCompare(values: [..] T, bigFirst = false)->s32
{
    if bigFirst do
        return pickCompare(values, func(x, y: T)->s32 => y <=> x)
    return pickCompare(values, func(x, y: T)->s32 => x <=> y)
}

func(T) pickCompare(values: [..] T, cb: func||(T, T)->s32)->s32
{
    return cb(values[0], values[1])
}

#test
{
    var values: [2] SortNamedItem = [{rank: 1, total: 20}, {rank: 0, total: 10}]
    @assert(pickCompare(values[ to ], func(x, y) => x.total <=> y.total) > 0)
}

#test
{
    var values: [2] SortNamedItem = [{rank: 1, total: 20}, {rank: 0, total: 10}]
    @assert(values[ to ].pickCompare(func(x, y) => x.total <=> y.total) > 0)
}

#test
{
    var values = [{rank: 1'u64, total: 20's64}, {rank: 0'u64, total: 10's64}]
    @assert(pickCompare(values[ to ], func(x, y) => x.total <=> y.total) > 0)
}

#test
{
    var values = [{rank: 1'u64, total: 20's64}, {rank: 0'u64, total: 10's64}]
    @assert(values[ to ].pickCompare(func(x, y) => x.total <=> y.total) > 0)
}
