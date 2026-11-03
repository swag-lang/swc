#global private

struct RuntimeCompareBox
{
    value: s32
}

impl RuntimeCompareBox
{
    #[Swag.NoInline]
    mtd const opEquals(other: RuntimeCompareBox)->bool
    {
        return .value == other.value
    }

    #[Swag.NoInline]
    mtd const opEquals(value: s32)->bool
    {
        return .value == value
    }

    #[Swag.NoInline]
    mtd const opCompare(other: RuntimeCompareBox)->s32
    {
        if .value < other.value do return -7
        if .value > other.value do return 9
        return 0
    }

    #[Swag.NoInline]
    mtd const opCompare(value: s32)->s32
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

    Swag.require(lhs.opEquals(rhs))
    Swag.require(not lhs.opEquals(other))
    Swag.require(lhs == rhs)
    Swag.require(not (lhs != rhs))
    Swag.require(lhs != other)
    Swag.require(not (lhs == other))
}

#test
{
    var lhs = RuntimeCompareBox{value: 12}

    #assert(#typeof(lhs == 12) == bool)
    #assert(#typeof(lhs <=> 18) == s32)

    Swag.require(lhs == 12)
    Swag.require(lhs != 5)
    Swag.require((lhs <=> 18) == -3)
}

#test
{
    var smaller = RuntimeCompareBox{value: 10}
    var larger  = RuntimeCompareBox{value: 20}

    Swag.require(smaller < larger)
    Swag.require(smaller <= larger)
    Swag.require(not (smaller > larger))
    Swag.require(not (smaller >= larger))
    Swag.require((smaller <=> larger) == -7)
}

#test
{
    var larger  = RuntimeCompareBox{value: 20}
    var smaller = RuntimeCompareBox{value: 10}

    Swag.require(larger > smaller)
    Swag.require(larger >= smaller)
    Swag.require(not (larger < smaller))
    Swag.require(not (larger <= smaller))
    Swag.require((larger <=> smaller) == 9)
}

#test
{
    var lhs = RuntimeCompareBox{value: 15}
    var rhs = RuntimeCompareBox{value: 15}

    Swag.require(not (lhs < rhs))
    Swag.require(lhs <= rhs)
    Swag.require(not (lhs > rhs))
    Swag.require(lhs >= rhs)
    Swag.require((lhs <=> rhs) == 0)
}

#test
{
    var lhs = RuntimeCompareBox{value: 8}

    Swag.require(lhs < 9)
    Swag.require(lhs <= 8)
    Swag.require(lhs > 7)
    Swag.require(lhs >= 8)
    Swag.require(not (lhs < 8))
    Swag.require(not (lhs > 8))
    Swag.require((lhs <=> 9) == -3)
    Swag.require((lhs <=> 7) == 4)
    Swag.require((lhs <=> 8) == 0)
}
