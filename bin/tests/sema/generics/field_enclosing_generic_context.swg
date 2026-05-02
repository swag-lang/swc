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

#test
{
    let wrapped: WrapperImplicit'u16
    let doubled: DoubleBufferImplicit'(u8, 4)
    let renamed: RenamedDoubleBufferImplicit'(u16, 3)
    let reordered: ReorderedRenamedDoubleBufferImplicit'(5, u32)
    let renamedWrapper: RenamedWrapperImplicit'(bool, 7)

    #assert(#typeof(wrapped.item.value) == u16)
    #assert(#typeof(doubled.first.values) == #type [4] u8)
    #assert(#typeof(doubled.second.values) == #type [4] u8)
    #assert(#typeof(renamed.first.values) == #type [3] u16)
    #assert(#typeof(renamed.second.values) == #type [3] u16)
    #assert(#typeof(reordered.first.values) == #type [5] u32)
    #assert(#typeof(reordered.second.values) == #type [5] u32)
    #assert(#typeof(renamedWrapper.item.value) == bool)
}
