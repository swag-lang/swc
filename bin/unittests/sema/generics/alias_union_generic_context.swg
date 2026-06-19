#global fileprivate

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

func(T) localAliasUnionValue()->ValueOrPtrAlias2
{
    struct Local
    {
        item: ValueOrPtrAlias2
    }

    let data: Local
    return data.item
}

func semaTest001()
{
    let wrapped: WrapperAliasUnion's32

    #assert(#typeof(wrapped.item.value) == s32)
    #assert(#typeof(localAliasUnionValue'u16().value) == u16)
}
