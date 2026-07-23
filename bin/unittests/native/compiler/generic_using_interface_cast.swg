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
    mtd impl baseValue()->s32    => .valueField
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
    other: s32
}

// The returned interface borrows the storage it was created from, so the caller
// provides storage that outlives the call.
func(T) makeInterface(object: *T, value: s32)->IGenericUsingCast
{
    object.valueField = value
    return cast(IGenericUsingCast) dref object
}

#test
{
    var wrapper: GenericUsingWrapper
    let itf = makeInterface(&wrapper, 91)
    @assert(itf.baseValue() == 91)
    @assert(itf.partialValue() == 101)
}
