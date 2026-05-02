#global fileprivate

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

func(T) functionLocalImplicitBox()->bool
{
    struct Local
    {
        item: Box
    }

    let data: Local
    return #typeof(data.item.value) == T
}

func(T, N: s32) functionLocalImplicitBuffer()->bool
{
    struct Local
    {
        item: Buffer
    }

    let data: Local
    return #typeof(data.item.values) == #type [N] T
}

func(T, V) functionLocalPartialBox()->bool
{
    struct Local
    {
        item: MiddleDefaultBox'T
    }

    let data: Local
    return #typeof(data.item.first) == T and #typeof(data.item.second) == string and #typeof(data.item.third) == V
}

func(T) functionLocalExplicitPrefixValue()->bool
{
    struct Local
    {
        item: PrefixDefaultBuffer'3
    }

    let data: Local
    return #typeof(data.item.values) == #type [3] T
}

struct(T) MethodTypeShadowHolder
{
}

impl MethodTypeShadowHolder
{
    func(var T) localUsesMethodType(value: T)->bool
    {
        struct Local
        {
            item: Box
        }

        let data: Local
        return #typeof(data.item.value) == T and #typeof(value) == T
    }
}

struct(T, N: s32) MethodConstShadowHolder
{
}

impl MethodConstShadowHolder
{
    func(const N: s32) localUsesMethodConst(const me)->bool
    {
        struct Local
        {
            item: Buffer
        }

        let data: Local
        return #typeof(data.item.values) == #type [N] T
    }
}

#test
{
    let typeShadowHolder: MethodTypeShadowHolder'u16
    let constShadowHolder: MethodConstShadowHolder'(u16, 9)

    #assert(functionLocalImplicitBox'u16())
    #assert(functionLocalImplicitBuffer'(u8, 4)())
    #assert(functionLocalPartialBox'(bool, f32)())
    #assert(functionLocalExplicitPrefixValue's64())
    #assert(typeShadowHolder.localUsesMethodType'bool(true))
    #assert(constShadowHolder.localUsesMethodConst'4())
}
