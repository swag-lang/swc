#global fileprivate

struct(T) Box
{
    value: T
}

struct(T, N: s32) Buffer
{
    values: [N] T
}

struct(T) WrapperImplicit
{
    item: Box
}

struct(T, N: s32) DoubleBufferImplicit
{
    first: Buffer
    second: Buffer
}

struct(U, M: s32) RenamedDoubleBufferImplicit
{
    first: Buffer
    second: Buffer
}

struct(M: s32, U) ReorderedRenamedDoubleBufferImplicit
{
    first: Buffer
    second: Buffer
}

struct(U, M: s32) RenamedWrapperImplicit
{
    item: Box
}

struct(N: s32 = 2, T) PrefixDefaultBuffer
{
    values: [N] T
}

struct(U) PrefixDefaultHolderImplicit
{
    item: PrefixDefaultBuffer
}

struct(T, U = string, V) MiddleDefaultBox
{
    first: T
    second: U
    third: V
}

struct(A, B) MiddleDefaultHolderImplicit
{
    item: MiddleDefaultBox
}

#test
{
    let wrapped: WrapperImplicit'u16
    let doubled: DoubleBufferImplicit'(u8, 4)
    let renamed: RenamedDoubleBufferImplicit'(u16, 3)
    let reordered: ReorderedRenamedDoubleBufferImplicit'(5, u32)
    let renamedWrapper: RenamedWrapperImplicit'(bool, 7)
    let prefixDefaultHolder: PrefixDefaultHolderImplicit'u8
    let middleDefaultHolder: MiddleDefaultHolderImplicit'(u16, f32)

    #assert(#typeof(wrapped.item.value) == u16)
    #assert(#typeof(doubled.first.values) == #type [4] u8)
    #assert(#typeof(doubled.second.values) == #type [4] u8)
    #assert(#typeof(renamed.first.values) == #type [3] u16)
    #assert(#typeof(renamed.second.values) == #type [3] u16)
    #assert(#typeof(reordered.first.values) == #type [5] u32)
    #assert(#typeof(reordered.second.values) == #type [5] u32)
    #assert(#typeof(renamedWrapper.item.value) == bool)
    #assert(#typeof(prefixDefaultHolder.item.values) == #type [2] u8)
    #assert(#typeof(middleDefaultHolder.item.first) == u16)
    #assert(#typeof(middleDefaultHolder.item.second) == string)
    #assert(#typeof(middleDefaultHolder.item.third) == f32)
}
