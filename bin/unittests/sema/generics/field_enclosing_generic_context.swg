#global private

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
    first:  Buffer
    second: Buffer
}

struct(U, M: s32) RenamedDoubleBufferImplicit
{
    first:  Buffer
    second: Buffer
}

struct(M: s32, U) ReorderedRenamedDoubleBufferImplicit
{
    first:  Buffer
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
    first:  T
    second: U
    third:  V
}

struct(A, B) MiddleDefaultHolderImplicit
{
    item: MiddleDefaultBox
}

struct(A, B) NestedMiddleDefaultHolderImplicit
{
    inner: MiddleDefaultHolderImplicit
}

struct(T, U = T) TwinImplicitBox
{
    first:  T
    second: U
}

struct(A) TwinImplicitHolder
{
    item: TwinImplicitBox
}

struct(T, N: s32, M: s32 = N) TrailingValueDefaultBuffer
{
    values: [M] T
}

struct(A, B: s32) TrailingValueDefaultHolder
{
    item: TrailingValueDefaultBuffer
}

struct(N: s32 = 2, T, M: s32 = N) SplitValueDefaultBuffer
{
    values: [M] T
}

struct(A) SplitValueDefaultHolder
{
    item: SplitValueDefaultBuffer
}

struct(U, M: s32) MethodBufferContext {}

struct(A, B) PartialMiddleDefaultHolder
{
    item: MiddleDefaultBox'A
}

struct(A, B: s32) PartialTrailingValueDefaultHolder
{
    item: TrailingValueDefaultBuffer'A
}

struct(A, B: s32) PartialBufferHolder
{
    item: Buffer'A
}

struct(A) ExplicitPrefixValueHolder
{
    item: PrefixDefaultBuffer'3
}

struct(A) ExplicitSplitValueHolder
{
    item: SplitValueDefaultBuffer'3
}

struct(A, B) PartialTailOnlyHolder
{
    item: MiddleDefaultBox'(A, f64)
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

struct(T) AnonymousStructFieldHolder
{
    inner: struct
    {
        item: Box
    }
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

impl MethodBufferContext
{
    func(var X) makeWithDistinctName(const me)->Buffer
    {
        var data: Buffer
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

    mtd const defaultCount(value: s32 = M)->s32     => value
    mtd const defaultTyped(value: U = cast(U) M)->U => value
}

func semaTest001()
{
    var wrapped:                    WrapperImplicit'u16 = undefined
    var doubled:                    DoubleBufferImplicit'(u8, 4) = undefined
    var renamed:                    RenamedDoubleBufferImplicit'(u16, 3) = undefined
    var reordered:                  ReorderedRenamedDoubleBufferImplicit'(5, u32) = undefined
    var renamedWrapper:             RenamedWrapperImplicit'(bool, 7) = undefined
    var prefixDefaultHolder:        PrefixDefaultHolderImplicit'u8 = undefined
    var middleDefaultHolder:        MiddleDefaultHolderImplicit'(u16, f32) = undefined
    var nestedMiddleDefaultHolder:  NestedMiddleDefaultHolderImplicit'(u16, f32) = undefined
    var twinImplicitHolder:         TwinImplicitHolder's64 = undefined
    var trailingValueDefaultHolder: TrailingValueDefaultHolder'(u16, 6) = undefined
    var splitValueDefaultHolder:    SplitValueDefaultHolder'u32 = undefined
    let methodBufferContext:        MethodBufferContext'(u16, 9)
    let distinctMethodBuffer = methodBufferContext.makeWithDistinctName'f32()
    var partialMiddleDefaultHolder:        PartialMiddleDefaultHolder'(u32, f64) = undefined
    var partialTrailingValueDefaultHolder: PartialTrailingValueDefaultHolder'(u16, 8) = undefined
    var partialBufferHolder:               PartialBufferHolder'(bool, 5) = undefined
    var explicitPrefixValueHolder:         ExplicitPrefixValueHolder'u8 = undefined
    var explicitSplitValueHolder:          ExplicitSplitValueHolder'u16 = undefined
    var partialTailOnlyHolder:             PartialTailOnlyHolder'(bool, f32) = undefined
    var composedTypeDefaultHolder:         ComposedTypeDefaultHolder's16 = undefined
    var sizeofDefaultHolder:               SizeofDefaultHolder'u64 = undefined
    var anonymousStructFieldHolder:        AnonymousStructFieldHolder'bool = undefined
    var anonymousStructBufferHolder:       AnonymousStructBufferHolder'(u8, 4) = undefined
    var anonymousUnionFieldHolder:         AnonymousUnionFieldHolder's32 = undefined

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
    #assert(#typeof(nestedMiddleDefaultHolder.inner.item.first) == u16)
    #assert(#typeof(nestedMiddleDefaultHolder.inner.item.second) == string)
    #assert(#typeof(nestedMiddleDefaultHolder.inner.item.third) == f32)
    #assert(#typeof(twinImplicitHolder.item.first) == s64)
    #assert(#typeof(twinImplicitHolder.item.second) == s64)
    #assert(#typeof(trailingValueDefaultHolder.item.values) == #type [6] u16)
    #assert(#typeof(splitValueDefaultHolder.item.values) == #type [2] u32)
    #assert(#typeof(distinctMethodBuffer.values) == #type [9] u16)
    #assert(#typeof(partialMiddleDefaultHolder.item.first) == u32)
    #assert(#typeof(partialMiddleDefaultHolder.item.second) == string)
    #assert(#typeof(partialMiddleDefaultHolder.item.third) == f64)
    #assert(#typeof(partialTrailingValueDefaultHolder.item.values) == #type [8] u16)
    #assert(#typeof(partialBufferHolder.item.values) == #type [5] bool)
    #assert(#typeof(explicitPrefixValueHolder.item.values) == #type [3] u8)
    #assert(#typeof(explicitSplitValueHolder.item.values) == #type [3] u16)
    #assert(#typeof(partialTailOnlyHolder.item.first) == bool)
    #assert(#typeof(partialTailOnlyHolder.item.second) == f64)
    #assert(#typeof(partialTailOnlyHolder.item.third) == f32)
    #assert(#typeof(composedTypeDefaultHolder.item.value) == Box's16)
    #assert(#typeof(composedTypeDefaultHolder.item.value.value) == s16)
    #assert(#typeof(sizeofDefaultHolder.item.values) == #type [8] u8)
    #assert(#typeof(anonymousStructFieldHolder.inner.item.value) == bool)
    #assert(#typeof(anonymousStructBufferHolder.inner.item.values) == #type [4] u8)
    #assert(#typeof(anonymousUnionFieldHolder.inner.item.value) == s32)
    #assert(methodBufferContext.localStructInferenceWorks())
    #assert(methodBufferContext.defaultCount() == 9)
    #assert(#typeof(methodBufferContext.defaultTyped()) == u16)
    #assert(methodBufferContext.defaultTyped() == 9'u16)
}
