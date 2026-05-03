#global fileprivate

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

    var data: Local
    data.item.first = value
    data.item.second = "ok"
    data.item.third = tail
    return data.item.third
}

func(U) localAliasPrefixBuffer(value: U)->U
{
    struct Local
    {
        item: PrefixDefaultAlias2'3
    }

    var data: Local
    data.item.values[0] = value
    return data.item.values[0]
}

#test
{
    var partial: AliasPartialHolder'(u32, f64)
    var prefix: AliasExplicitPrefixHolder'u8
    let tail = localAliasPartialTail'(bool, f32)(true, 1.5)
    let value = localAliasPrefixBuffer'u16(12)

    partial.item.first = 7
    partial.item.second = "ok"
    partial.item.third = 2.5
    prefix.item.values[0] = 3
    prefix.item.values[2] = 5

    #assert(#typeof(partial.item.second) == string)
    #assert(#typeof(prefix.item.values) == #type [3] u8)
    #assert(#typeof(tail) == f32)
    #assert(#typeof(value) == u16)
    @assert(partial.item.first == 7'u32)
    @assert(partial.item.second == "ok")
    @assert(partial.item.third == 2.5'f64)
    @assert(prefix.item.values[0] == 3'u8)
    @assert(prefix.item.values[2] == 5'u8)
    @assert(tail == 1.5'f32)
    @assert(value == 12'u16)
}
