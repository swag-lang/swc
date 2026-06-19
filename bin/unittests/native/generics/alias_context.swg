#global fileprivate

func(T, U) freeAccepts(first: T, second: U)->bool
{
    return #typeof(first) == T and #typeof(second) == U and first == true and second == 2.5'f32
}

struct(T) Box
{
    value: T
}

alias GenericFreeAlias = freeAccepts
alias GenericBoxAlias  = Box
alias GenericBoxAlias2 = GenericBoxAlias

func(U) functionLocalAliasBox(value: U)->U
{
    struct Local
    {
        item: GenericBoxAlias2
    }

    var data: Local
    data.item.value = value
    return data.item.value
}

struct(U) WrapperAliasBox
{
    item: GenericBoxAlias2
}

struct(T) Vector3
{
    x: T
    y: T
    z: T
}

impl Vector3
{
    func dot(a: const &Vector3'T, b: const &Vector3'T)->T
    {
        return a.x * b.x + a.y * b.y + a.z * b.z
    }
}

alias VectorAlias  = Vector3
alias VectorAlias2 = VectorAlias

func choose(value: bool, other: f32)->s32
{
    return 1
}

func(T, U) choose(value: T, other: U)->bool
{
    return #typeof(value) == T and #typeof(other) == U and value == true and other == 0.0'f32
}

#test
{
    let ok = GenericFreeAlias'(bool)(true, 2.5'f32)
    let local = functionLocalAliasBox'u16(12)
    let boxed: GenericBoxAlias'bool = {value: true}
    let wrapped: WrapperAliasBox'f32 = {item: {value: 3.5}}

    #assert(#typeof(ok) == bool)
    #assert(#typeof(local) == u16)
    #assert(#typeof(boxed.value) == bool)
    #assert(#typeof(wrapped.item.value) == f32)
    @assert(ok)
    @assert(local == 12'u16)
    @assert(boxed.value == true)
    @assert(wrapped.item.value == 3.5'f32)
}

#test
{
    var a: VectorAlias2's32 = {x: 1, y: 2, z: 3}
    var b: VectorAlias2's32 = {x: 4, y: 5, z: 6}
    let d = VectorAlias2's32.dot(&a, &b)
    let picked = choose'(bool)(true, 0.0'f32)

    #assert(#typeof(d) == s32)
    #assert(#typeof(picked) == bool)
    @assert(d == 32)
    @assert(picked)
}
