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
        return cast(s32, input)
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
    Swag.require(not (boxed is IConstrainedDynamicValue))
}

struct(T) GenericConstrainedDynamicValue
{
    number: T
}

impl IConstrainedDynamicValue for GenericConstrainedDynamicValue
{
    mtd value()->s32 where #sizeof(T) == 4
    {
        return cast(s32, .number)
    }
}

#test
{
    var accepted  = GenericConstrainedDynamicValue's32{42}
    let boxedAccepted: any = &accepted
    let converted = catch cast(IConstrainedDynamicValue?, boxedAccepted)
    Swag.require(converted != null)
    Swag.require(converted.value() == 42)

    var rejected = GenericConstrainedDynamicValue's64{42}
    #assert(not (GenericConstrainedDynamicValue's64 is IConstrainedDynamicValue))
    let boxedRejected: any = &rejected
    Swag.require(not (boxedRejected is IConstrainedDynamicValue))
}

#test
{
    var value:  ConstrainedDynamicValue
    let direct: IConstrainedDynamicValue = &value
    let boxed:  any = &value
    let converted   = catch cast(IConstrainedDynamicValue?, boxed)
    Swag.require(converted != null)
    if let view = converted
    {
        Swag.require(view.value() == 42)
        Swag.require(view == direct)
    }
}
