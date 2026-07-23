#global private

struct(T) Box
{
    value: T
}

struct(T, N: s32) Buffer
{
    values: [N] T
}

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

func(U) functionLocalImplicitRenamedBox(value: U)->U
{
    struct Local
    {
        item: Box
    }

    var data: Local
    data.item.value = value
    return data.item.value
}

func(U, M: s32) functionLocalImplicitRenamedBuffer()->U
{
    struct Local
    {
        item: Buffer
    }

    var data: Local
    data.item.values[0] = cast(U) M
    return data.item.values[0]
}

func(A, B) functionLocalRenamedPartialBox(first: A, third: B)->B
{
    struct Local
    {
        item: MiddleDefaultBox'A
    }

    var data: Local = undefined
    data.item.first  = first
    data.item.second = "ok"
    data.item.third  = third
    return data.item.third
}

func(U) functionLocalRenamedExplicitPrefixValue()->U
{
    struct Local
    {
        item: PrefixDefaultBuffer'3
    }

    var data: Local
    data.item.values[2] = cast(U) 21
    return data.item.values[2]
}

func(T) functionReturnOnlyFactory(value: s32)->T
{
    return cast(T) value
}

func(T) functionReturnOnlyForward(value: s32)->T
{
    return functionReturnOnlyFactory(value)
}

struct(T) MethodTypeShadowHolder {}

impl MethodTypeShadowHolder
{
    func(var T) localUsesMethodType(value: T)->T
    {
        struct Local
        {
            item: Box
        }

        var data: Local
        data.item.value = value
        return data.item.value
    }
}

struct(T, N: s32) MethodConstShadowHolder {}

impl MethodConstShadowHolder
{
    func(const N: s32) localUsesMethodConst(const me)->s32
    {
        struct Local
        {
            item: Buffer
        }

        let data: Local
        return #sizeof(data.item.values) / #sizeof(T)
    }
}

#test
{
    let value = functionLocalImplicitRenamedBox'u16(12)
    let first = functionLocalImplicitRenamedBuffer'(u8, 4)()
    let tail = functionLocalRenamedPartialBox'(bool, f32)(true, 4.5)
    let explicit = functionLocalRenamedExplicitPrefixValue's64()
    let forwarded = functionReturnOnlyForward'u16(12)

    #assert(#typeof(value) == u16)
    #assert(#typeof(first) == u8)
    #assert(#typeof(tail) == f32)
    #assert(#typeof(explicit) == s64)
    #assert(#typeof(forwarded) == u16)
    @assert(value == 12'u16)
    @assert(first == 4'u8)
    @assert(tail == 4.5'f32)
    @assert(explicit == 21's64)
    @assert(forwarded == 12'u16)
}

#test
{
    let typeShadowHolder:  MethodTypeShadowHolder'u16
    let constShadowHolder: MethodConstShadowHolder'(u16, 9)

    let value = typeShadowHolder.localUsesMethodType'bool(true)
    let count = constShadowHolder.localUsesMethodConst'4()

    #assert(#typeof(value) == bool)
    @assert(value == true)
    @assert(count == 4)
}
