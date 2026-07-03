#global private

interface IGenericUsingCast
{
    mtd baseValue()->s32;
    mtd partialValue()->s32;
}

struct GenericUsingBase
{
    valueField: s32
}

impl IGenericUsingCast for GenericUsingBase
{
    mtd impl baseValue()->s32 => .valueField
    mtd impl partialValue()->s32 => -1
}

struct GenericUsingMiddle
{
    using base: GenericUsingBase
}

struct GenericUsingPartial
{
    using middle: GenericUsingMiddle
}

impl IGenericUsingCast for GenericUsingPartial
{
    mtd impl partialValue()->s32 => 101
}

struct GenericUsingWrapper
{
    using partial: GenericUsingPartial
    other:      s32
}

func(T) makeInterface(value: s32)->IGenericUsingCast
{
    var object: T
    object.valueField = value
    return cast(IGenericUsingCast) object
}

#test
{
    let itf = makeInterface'GenericUsingWrapper(91)
    @assert(itf.baseValue() == 91)
    @assert(itf.partialValue() == 101)
}
