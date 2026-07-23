#global private

interface IGenericPointerCast
{
    mtd get()->s32;
    mtd fallback()->s32;
}

struct GenericPointerCastBase
{
    itf:   IGenericPointerCast
    value: s32 = 7
}

struct GenericPointerCastBox
{
    using base: GenericPointerCastBase
    value: s32 = 42
}

impl IGenericPointerCast for GenericPointerCastBase
{
    mtd impl get()->s32 => .value
    mtd impl fallback()->s32 => .value + 70
}

impl IGenericPointerCast for GenericPointerCastBox
{
    mtd impl get()->s32 => .value
}

func(T) getGenericPointerCastValue()->s32
{
    let ptr = cast(#null *T) @alloc(#sizeof(T))
    ptr.base.value = 7
    ptr.value      = 42
    ptr.itf        = cast(IGenericPointerCast) dref ptr
    return ptr.itf.get() + ptr.itf.fallback()
}

func runGenericPointerInterfaceCast()->bool
{
    return getGenericPointerCastValue'GenericPointerCastBox() == 119
}

#test
{
    @assert(runGenericPointerInterfaceCast())
}
