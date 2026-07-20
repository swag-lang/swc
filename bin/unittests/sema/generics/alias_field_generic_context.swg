#global private

struct(T, U = string, V) MiddleDefaultBox
{
    first:  T
    second: U
    third:  V
}

struct(N: s32 = 2, T) PrefixDefaultBuffer
{
    values: [N] T
}

alias MiddleDefaultAlias  = MiddleDefaultBox
alias MiddleDefaultAlias2 = MiddleDefaultAlias
alias PrefixDefaultAlias  = PrefixDefaultBuffer
alias PrefixDefaultAlias2 = PrefixDefaultAlias

struct(A, B) AliasPartialHolder
{
    item: MiddleDefaultAlias2'A
}

struct(A) AliasExplicitPrefixHolder
{
    item: PrefixDefaultAlias2'3
}

func(T, V) localAliasPartialTail(value: T, tail: V)->V
{
    struct Local
    {
        item: MiddleDefaultAlias2'T
    }

    var data: Local = undefined
    data.item.first = value
    data.item.second = "ok"
    data.item.third = tail
    return data.item.third
}

func(U) localAliasPrefixBuffer()->PrefixDefaultAlias2'3
{
    struct Local
    {
        item: PrefixDefaultAlias2'3
    }

    let data: Local
    return data.item
}

func semaTest001()
{
    var partial: AliasPartialHolder'(u32, f64) = undefined
    let prefix: AliasExplicitPrefixHolder'u8

    #assert(#typeof(partial.item.first) == u32)
    #assert(#typeof(partial.item.second) == string)
    #assert(#typeof(partial.item.third) == f64)
    #assert(#typeof(prefix.item.values) == #type [3] u8)
    #assert(#typeof(localAliasPartialTail'(bool, f32)(true, 1.5)) == f32)
    #assert(#typeof(localAliasPrefixBuffer'u16().values) == #type [3] u16)
}
