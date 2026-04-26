#global fileprivate

struct CompareSpecBox
{
    value: s32
}

impl CompareSpecBox
{
    #[Swag.NoInline]
    mtd const opEquals(other: const &CompareSpecBox)->bool
    {
        return .value == other.value
    }

    #[Swag.NoInline]
    mtd const opEquals(value: s32)->bool
    {
        return .value == value
    }

    #[Swag.NoInline]
    mtd const opCompare(other: const &CompareSpecBox)->s32
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
    let lhs = CompareSpecBox{value: 42}
    let rhs = CompareSpecBox{value: 42}
    let eq: bool = lhs == rhs
    let ne: bool = lhs != rhs

    #assert(#typeof(lhs == rhs) == bool)
    #assert(#typeof(lhs != rhs) == bool)
    #assert(#typeof(eq) == bool)
    #assert(#typeof(ne) == bool)
}

#test
{
    let lhs = CompareSpecBox{value: 42}
    let eq: bool = lhs == 42
    let ne: bool = lhs != 41

    #assert(#typeof(lhs == 42) == bool)
    #assert(#typeof(lhs != 41) == bool)
    #assert(#typeof(eq) == bool)
    #assert(#typeof(ne) == bool)
}

#test
{
    let lhs = CompareSpecBox{value: 10}
    let rhs = CompareSpecBox{value: 20}
    let lt: bool = lhs < rhs
    let le: bool = lhs <= rhs
    let gt: bool = lhs > rhs
    let ge: bool = lhs >= rhs
    let cmp: s32 = lhs <=> rhs

    #assert(#typeof(lhs < rhs) == bool)
    #assert(#typeof(lhs <= rhs) == bool)
    #assert(#typeof(lhs > rhs) == bool)
    #assert(#typeof(lhs >= rhs) == bool)
    #assert(#typeof(lhs <=> rhs) == s32)
    #assert(#typeof(lt) == bool)
    #assert(#typeof(le) == bool)
    #assert(#typeof(gt) == bool)
    #assert(#typeof(ge) == bool)
    #assert(#typeof(cmp) == s32)
}

#test
{
    let lhs = CompareSpecBox{value: 20}
    let rhs = CompareSpecBox{value: 10}
    let lt: bool = lhs < rhs
    let le: bool = lhs <= rhs
    let gt: bool = lhs > rhs
    let ge: bool = lhs >= rhs
    let cmp: s32 = lhs <=> rhs

    #assert(#typeof(lt) == bool)
    #assert(#typeof(le) == bool)
    #assert(#typeof(gt) == bool)
    #assert(#typeof(ge) == bool)
    #assert(#typeof(cmp) == s32)
}

#test
{
    let lhs = CompareSpecBox{value: 15}
    let rhs = CompareSpecBox{value: 15}
    let lt: bool = lhs < rhs
    let le: bool = lhs <= rhs
    let gt: bool = lhs > rhs
    let ge: bool = lhs >= rhs
    let cmp: s32 = lhs <=> rhs

    #assert(#typeof(lt) == bool)
    #assert(#typeof(le) == bool)
    #assert(#typeof(gt) == bool)
    #assert(#typeof(ge) == bool)
    #assert(#typeof(cmp) == s32)
}

#test
{
    let lhs = CompareSpecBox{value: 8}
    let lt: bool = lhs < 9
    let le: bool = lhs <= 8
    let gt: bool = lhs > 7
    let ge: bool = lhs >= 8
    let cmpLower: s32 = lhs <=> 9
    let cmpUpper: s32 = lhs <=> 7
    let cmpEqual: s32 = lhs <=> 8

    #assert(#typeof(lt) == bool)
    #assert(#typeof(le) == bool)
    #assert(#typeof(gt) == bool)
    #assert(#typeof(ge) == bool)
    #assert(#typeof(cmpLower) == s32)
    #assert(#typeof(cmpUpper) == s32)
    #assert(#typeof(cmpEqual) == s32)
}
