#global private

union(T) ValueOrPtr
{
    value: T
    ptr:   *T
}

alias ValueOrPtrAlias  = ValueOrPtr
alias ValueOrPtrAlias2 = ValueOrPtrAlias

struct(U) WrapperAliasUnion
{
    item: ValueOrPtrAlias2
}

func(T) localAliasUnionValue(value: T)->T
{
    struct Local
    {
        item: ValueOrPtrAlias2
    }

    var data: Local
    data.item.value = value
    return data.item.value
}

#test
{
    var wrapped: WrapperAliasUnion's32
    let local = localAliasUnionValue'u16(12)

    wrapped.item.value = 42

    #assert(#typeof(wrapped.item.value) == s32)
    #assert(#typeof(local) == u16)
    @assert(wrapped.item.value == 42)
    @assert(local == 12'u16)
}
