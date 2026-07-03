#global private

union(T) ValueOrPtr
{
    value: T
    ptr:   *T
}

impl ValueOrPtr
{
    mtd sameType(other: T)->bool
    {
        return #typeof(other) == T
    }

    mtd(U) pair(other: U)->bool
    {
        return #typeof(.value) == T and #typeof(other) == U
    }

    func makeValue(value: T)->ValueOrPtr'T
    {
        return {value: value}
    }
}

alias ValueOrPtrAlias  = ValueOrPtr
alias ValueOrPtrAlias2 = ValueOrPtrAlias

func(T) takeValue(boxed: ValueOrPtr'T)->T
{
    return boxed.value
}

#test
{
    var boxed = ValueOrPtr's32{value: 10}
    @assert(boxed.sameType(12))
    @assert(boxed.pair'bool(true))
}

#test
{
    let boxed1 = ValueOrPtr's32.makeValue(42)
    let boxed2 = ValueOrPtrAlias2's32.makeValue(24)

    #assert(#typeof(boxed1.value) == s32)
    #assert(#typeof(boxed2.value) == s32)
    @assert(boxed1.value == 42)
    @assert(boxed2.value == 24)
}

#test
{
    let value = takeValue({value: 10's32})
    #assert(#typeof(value) == s32)
    @assert(value == 10)
}
