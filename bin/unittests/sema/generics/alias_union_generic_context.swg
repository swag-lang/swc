#global private

union(T) ValueOrPtr
{
    value: T

    // The pointer view of the same storage starts null, so the union keeps a zero default.
    late ptr: *T
}

alias ValueOrPtrAlias  = ValueOrPtr
alias ValueOrPtrAlias2 = ValueOrPtrAlias

struct(U) WrapperAliasUnion
{
    item: ValueOrPtrAlias2
}

func(T) localAliasUnionValue()->ValueOrPtrAlias2
{
    struct Local
    {
        item: ValueOrPtrAlias2
    }

    var data: Local
    data.item.value = 0
    return data.item
}

func semaTest001()
{
    var wrapped: WrapperAliasUnion's32

    #assert(#typeof(wrapped.item.value) == s32)
    #assert(#typeof(localAliasUnionValue'u16().value) == u16)
}
