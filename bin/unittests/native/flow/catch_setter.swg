#global private

struct SetterValue
{
    text:    string?
    padding: [40] u8
}

impl SetterValue
{
    #[Swag.Implicit, Swag.Inline]
    mtd const opCast()->string?
    {
        Swag.assert(.padding[39] == (.text == null ? 0 : 91))
        return .text
    }

    #[Swag.Implicit]
    mtd opSet(value: string?)
    {
        .text = value
    }

    mtd opPostCopy() {}
    mtd opDrop()
    {
        .text = null
    }
}

#[Swag.NoInline]
func produceSetterValue(failing: bool)->SetterValue fail
{
    if failing do
        fail 73's32
    var result: SetterValue
    result.text        = "setter value"
    result.padding[39] = 91
    return result
}

struct SetterReceiver
{
    value: SetterValue
}

impl SetterReceiver
{
    #[Swag.NoInline]
    mtd direct(failing: bool)->bool fail
    {
        .value = catch produceSetterValue(failing) as error
        if error is s32 as number
        {
            Swag.assert(number[] == 73)
            Swag.assert(.value.text == null)
            return false
        }
        Swag.assert(error == null)
        Swag.assert(.value.text == "setter value")
        return true
    }

    #[Swag.NoInline]
    mtd staged(failing: bool)->bool fail
    {
        let value = catch produceSetterValue(failing) as error
        if error is s32 as number
        {
            Swag.assert(number[] == 73)
            Swag.assert(value.text == null)
            return false
        }
        Swag.assert(error == null)
        .value = value
        Swag.assert(.value.text == "setter value")
        return true
    }
}

#test
{
    var receiver: SetterReceiver
    Swag.assert(expect receiver.direct(false))
    Swag.assert(not expect receiver.direct(true))
    Swag.assert(expect receiver.direct(false))
}

#test
{
    var receiver: SetterReceiver
    Swag.assert(expect receiver.staged(false))
    Swag.assert(not expect receiver.staged(true))
    Swag.assert(expect receiver.staged(false))
}
