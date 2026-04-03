#global fileprivate

struct RuntimeCompareBox
{
    value: s32
}

impl RuntimeCompareBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd const opEquals(other: const &RuntimeCompareBox)->bool
    {
        return .value == other.value
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opEquals(value: s32)->bool
    {
        return .value == value
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opCmp(other: const &RuntimeCompareBox)->s32
    {
        if .value < other.value do return -7
        if .value > other.value do return 9
        return 0
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opCmp(value: s32)->s32
    {
        if .value < value do return -3
        if .value > value do return 4
        return 0
    }
}

#test
{
    var lhs   = RuntimeCompareBox{value: 42}
    var rhs   = RuntimeCompareBox{value: 42}
    var other = RuntimeCompareBox{value: 7}

    #assert(#typeof(lhs == rhs) == bool)
    #assert(#typeof(lhs != other) == bool)

    @assert(lhs.opEquals(rhs))
    @assert(!lhs.opEquals(other))
    @assert(lhs == rhs)
    @assert(!(lhs != rhs))
    @assert(lhs != other)
    @assert(!(lhs == other))
}

#test
{
    var lhs = RuntimeCompareBox{value: 12}

    #assert(#typeof(lhs == 12) == bool)
    #assert(#typeof(lhs <=> 18) == s32)

    @assert(lhs == 12)
    @assert(lhs != 5)
    @assert((lhs <=> 18) == -3)
}

#test
{
    var smaller = RuntimeCompareBox{value: 10}
    var larger  = RuntimeCompareBox{value: 20}

    @assert(smaller < larger)
    @assert(smaller <= larger)
    @assert(!(smaller > larger))
    @assert(!(smaller >= larger))
    @assert((smaller <=> larger) == -7)
}

#test
{
    var larger  = RuntimeCompareBox{value: 20}
    var smaller = RuntimeCompareBox{value: 10}

    @assert(larger > smaller)
    @assert(larger >= smaller)
    @assert(!(larger < smaller))
    @assert(!(larger <= smaller))
    @assert((larger <=> smaller) == 9)
}

#test
{
    var lhs = RuntimeCompareBox{value: 15}
    var rhs = RuntimeCompareBox{value: 15}

    @assert(!(lhs < rhs))
    @assert(lhs <= rhs)
    @assert(!(lhs > rhs))
    @assert(lhs >= rhs)
    @assert((lhs <=> rhs) == 0)
}

#test
{
    var lhs = RuntimeCompareBox{value: 8}

    @assert(lhs < 9)
    @assert(lhs <= 8)
    @assert(lhs > 7)
    @assert(lhs >= 8)
    @assert(!(lhs < 8))
    @assert(!(lhs > 8))
    @assert((lhs <=> 9) == -3)
    @assert((lhs <=> 7) == 4)
    @assert((lhs <=> 8) == 0)
}
