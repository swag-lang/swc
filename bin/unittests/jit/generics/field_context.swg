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

struct(T) WrapperImplicit
{
    item: Box
}

struct(U, M: s32) RenamedDoubleBufferImplicit
{
    first:  Buffer
    second: Buffer
}

struct(A, B) PartialMiddleDefaultHolder
{
    item: MiddleDefaultBox'A
}

struct(A) ExplicitPrefixValueHolder
{
    item: PrefixDefaultBuffer'3
}

struct(U, M: s32) MethodBufferContext {}

impl MethodBufferContext
{
    func(var X) makeWithDistinctName(const me)->Buffer
    {
        var data: Buffer
        data.values[0] = cast(U) 42
        return data
    }

    mtd const localStructInferenceWorks()->bool
    {
        struct Local
        {
            item: Buffer
        }

        let data: Local
        return #typeof(data.item.values) == #type [M] U
    }

    mtd const defaultCount(value: s32 = M)->s32 => value
    mtd const defaultTyped(value: U = cast(U) M)->U => value
}

func(T) functionLocalImplicitBox(value: T)->T
{
    struct Local
    {
        item: Box
    }

    var data: Local
    data.item.value = value
    return data.item.value
}

func(T, V) functionLocalPartialBox(value: T, tail: V)->V
{
    struct Local
    {
        item: MiddleDefaultBox'T
    }

    var data: Local = undefined
    data.item.first  = value
    data.item.second = "ok"
    data.item.third  = tail
    return data.item.third
}

#test
{
    var wrapped: WrapperImplicit'u16
    wrapped.item.value = 7
    @assert(wrapped.item.value == 7)
    #assert(#typeof(wrapped.item.value) == u16)

    var renamed: RenamedDoubleBufferImplicit'(u16, 3)
    renamed.first.values[0]  = 1
    renamed.second.values[2] = 9
    @assert(renamed.first.values[0] == 1'u16)
    @assert(renamed.second.values[2] == 9'u16)
    #assert(#typeof(renamed.first.values) == #type [3] u16)

    var partial: PartialMiddleDefaultHolder'(u32, f64) = undefined
    partial.item.first  = 11
    partial.item.second = "value"
    partial.item.third  = 2.5
    @assert(partial.item.first == 11'u32)
    @assert(partial.item.second == "value")
    @assert(partial.item.third == 2.5)
    #assert(#typeof(partial.item.second) == string)

    var explicitPrefix: ExplicitPrefixValueHolder'u8
    explicitPrefix.item.values[0] = 3
    explicitPrefix.item.values[2] = 5
    @assert(explicitPrefix.item.values[0] == 3'u8)
    @assert(explicitPrefix.item.values[2] == 5'u8)
    #assert(#typeof(explicitPrefix.item.values) == #type [3] u8)
}

#test
{
    let methodBufferContext: MethodBufferContext'(u16, 9)
    let distinctMethodBuffer = methodBufferContext.makeWithDistinctName'f32()

    @assert(methodBufferContext.localStructInferenceWorks())
    @assert(methodBufferContext.defaultCount() == 9)
    @assert(methodBufferContext.defaultTyped() == 9'u16)
    @assert(distinctMethodBuffer.values[0] == 42'u16)
    #assert(#typeof(distinctMethodBuffer.values) == #type [9] u16)
}

#test
{
    let value = functionLocalImplicitBox'u16(12)
    let tail = functionLocalPartialBox'(bool, f32)(true, 4.5)

    @assert(value == 12'u16)
    @assert(tail == 4.5'f32)
    #assert(#typeof(value) == u16)
    #assert(#typeof(tail) == f32)
}
