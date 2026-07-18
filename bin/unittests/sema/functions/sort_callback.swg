#global private
#global #[Swag.ExplicitNullability]

struct SortNamedItem
{
    rank:  u64
    total: s64
}

func(T) pickCompare(values: #nonull [..] T, bigFirst = false)->s32
{
    if bigFirst do
        return pickCompare(values, func(x, y: T)->s32 => y <=> x)
    return pickCompare(values, func(x, y: T)->s32 => x <=> y)
}

func(T) pickCompare(values: #nonull [..] T, cb: func||(T, T)->s32)->s32
{
    return cb(values[0], values[1])
}

func semaTest001()
{
    var values: [2] SortNamedItem = [{rank: 1, total: 20}, {rank: 0, total: 10}]
    let result = pickCompare(values[ to ], func(x, y) => x.total <=> y.total)
    #assert(#typeof(result) == s32)
}

func semaTest002()
{
    var values: [2] SortNamedItem = [{rank: 1, total: 20}, {rank: 0, total: 10}]
    let result = values[ to ].pickCompare(func(x, y) => x.total <=> y.total)
    #assert(#typeof(result) == s32)
}

func semaTest003()
{
    var values = [{rank: 1'u64, total: 20's64}, {rank: 0'u64, total: 10's64}]
    let result = pickCompare(values[ to ], func(x, y) => x.total <=> y.total)
    #assert(#typeof(result) == s32)
}

func semaTest004()
{
    var values = [{rank: 1'u64, total: 20's64}, {rank: 0'u64, total: 10's64}]
    let result = values[ to ].pickCompare(func(x, y) => x.total <=> y.total)
    #assert(#typeof(result) == s32)
}
