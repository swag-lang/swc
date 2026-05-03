#global fileprivate

struct(T) Box
{
    value: T
}

struct(T, N: s32) Buffer
{
    values: [N] T
}

struct(M: s32, U) ReorderedRenamedDoubleBufferImplicit
{
    first:  Buffer
    second: Buffer
}

struct(T, U = Box'T) ComposedTypeDefaultBox
{
    value: U
}

struct(A) ComposedTypeDefaultHolder
{
    item: ComposedTypeDefaultBox
}

struct(T, N: s32 = #sizeof(T)) SizeofDefaultBuffer
{
    values: [N] u8
}

struct(A) SizeofDefaultHolder
{
    item: SizeofDefaultBuffer
}

struct(T, N: s32) AnonymousStructBufferHolder
{
    inner: struct
    {
        item: Buffer
    }
}

struct(T) AnonymousUnionFieldHolder
{
    inner: union
    {
        item: Box
        alt:  Box
    }
}

#test
{
    var reordered: ReorderedRenamedDoubleBufferImplicit'(5, u32)
    reordered.first.values[0] = 11
    reordered.second.values[4] = 29

    #assert(#typeof(reordered.first.values) == #type [5] u32)
    @assert(reordered.first.values[0] == 11'u32)
    @assert(reordered.second.values[4] == 29'u32)
}

#test
{
    var composed: ComposedTypeDefaultHolder's16
    var sized: SizeofDefaultHolder'u64

    composed.item.value.value = 7
    sized.item.values[0] = 1
    sized.item.values[7] = 9

    #assert(#typeof(composed.item.value) == Box's16)
    #assert(#typeof(sized.item.values) == #type [8] u8)
    @assert(composed.item.value.value == 7's16)
    @assert(sized.item.values[0] == 1'u8)
    @assert(sized.item.values[7] == 9'u8)
}

#test
{
    var anonymousStruct: AnonymousStructBufferHolder'(u8, 4)
    var anonymousUnion: AnonymousUnionFieldHolder's32

    anonymousStruct.inner.item.values[0] = 3
    anonymousStruct.inner.item.values[3] = 5
    anonymousUnion.inner.item.value = 42

    #assert(#typeof(anonymousStruct.inner.item.values) == #type [4] u8)
    #assert(#typeof(anonymousUnion.inner.item.value) == s32)
    @assert(anonymousStruct.inner.item.values[0] == 3'u8)
    @assert(anonymousStruct.inner.item.values[3] == 5'u8)
    @assert(anonymousUnion.inner.item.value == 42)
}
