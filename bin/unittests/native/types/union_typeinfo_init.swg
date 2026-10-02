#global private

// A union whose default is all zero bytes is initialized by clearing its storage: its type info
// publishes no init hook. A union with a non-zero default keeps one, so a reflected allocation
// still receives that default.

struct UnionInitItem
{
    value: s32
}

union UnionInitZero
{
    bits:    u64
    pointer: *UnionInitItem?
}

union UnionInitLatePointer
{
    bits: u64
    late pointer: *UnionInitItem
}

union UnionInitText
{
    bits: u64
    text: string = "union-init-default"
}

func unionInitHook(type: typeinfo)->bool
{
    let structType = cast #assume(const *Swag.TypeInfoStruct) type
    return structType.opInit != null
}

#test
{
    Swag.assert(not unionInitHook(#typeof(UnionInitZero)))
    Swag.assert(not unionInitHook(#typeof(UnionInitLatePointer)))
    Swag.assert(unionInitHook(#typeof(UnionInitText)))

    var zero: UnionInitZero
    Swag.assert(zero.bits == 0)

    var text: UnionInitText
    Swag.assert(text.text == "union-init-default")
}
