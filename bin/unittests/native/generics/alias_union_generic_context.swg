#global private

union(T) ValueOrPtr
{
    value: T

    // The pointer view of the same storage starts null, so the union keeps a zero default.
    #[Swag.Late]
    ptr: *T
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
    Swag.assert(wrapped.item.value == 42)
    Swag.assert(local == 12'u16)
}
