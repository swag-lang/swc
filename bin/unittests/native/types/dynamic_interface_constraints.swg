#global private

interface IConstrainedDynamicValue
{
    mtd value()->s32
}

struct ConstrainedDynamicValue {}

impl IConstrainedDynamicValue for ConstrainedDynamicValue
{
    mtd(T) value(input: T)->s32 where #sizeof(T) == 4
    {
        return cast(s32) input
    }

    mtd value()->s32 where #sizeof(s32) == 4
    {
        let owner: typeinfo = ConstrainedDynamicValue
        Swag.assert(owner.kind == .Struct)
        return 42
    }
}

struct RejectedDynamicValue
{
    number: s32 = 42
}

impl IConstrainedDynamicValue for RejectedDynamicValue
{
    mtd value()->s32 where false
    {
        return .number
    }
}

#test
{
    var value: RejectedDynamicValue
    #assert(not (RejectedDynamicValue is IConstrainedDynamicValue))
    let boxed: any = &value
    Swag.assert(not (boxed is IConstrainedDynamicValue))
}

struct(T) GenericConstrainedDynamicValue
{
    number: T
}

impl IConstrainedDynamicValue for GenericConstrainedDynamicValue
{
    mtd value()->s32 where #sizeof(T) == 4
    {
        return cast(s32) .number
    }
}

#test
{
    var accepted  = GenericConstrainedDynamicValue's32{42}
    let boxedAccepted: any = &accepted
    let converted = cast #try(IConstrainedDynamicValue) boxedAccepted
    Swag.assert(converted != null)
    Swag.assert(converted.value() == 42)

    var rejected = GenericConstrainedDynamicValue's64{42}
    #assert(not (GenericConstrainedDynamicValue's64 is IConstrainedDynamicValue))
    let boxedRejected: any = &rejected
    Swag.assert(not (boxedRejected is IConstrainedDynamicValue))
}

#test
{
    var value:  ConstrainedDynamicValue
    let direct: IConstrainedDynamicValue = &value
    let boxed:  any = &value
    let converted   = cast #try (IConstrainedDynamicValue) boxed
    Swag.assert(converted != null)
    if let view = converted
    {
        Swag.assert(view.value() == 42)
        Swag.assert(view == direct)
    }
}
