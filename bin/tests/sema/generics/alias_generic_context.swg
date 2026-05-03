#global fileprivate

struct(T) Box
{
    value: T
}

alias GenericBoxAlias  = Box
alias GenericBoxAlias2 = GenericBoxAlias

func(U) functionLocalAliasBox()->bool
{
    struct Local
    {
        item: GenericBoxAlias2
    }

    let data: Local
    return #typeof(data.item.value) == U
}

struct(U) WrapperAliasBox
{
    item: GenericBoxAlias2
}

func semaTest001()
{
    #assert(functionLocalAliasBox'u16())

    let data: WrapperAliasBox'f32
    #assert(#typeof(data.item.value) == f32)
}
