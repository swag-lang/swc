#global private

func increment(value: *u32, amount: u32)
{
    value[] += amount
}

#[Swag.NoInline]
func functionAddress(action: func(*u32, u32))->const *void? => cast(const *void?) action

func invokeDeferred(value: *u32)
{
    let address = functionAddress(&increment)
    Swag.assert(address != null)
    let action = cast(func(*u32, u32)) address
    action(value, 3)
    defer
    {
        action(value, 7)
        discard Swag.getContext()
    }
}

#test
{
    var value = 0'u32
    invokeDeferred(&value)
    Swag.assert(value == 10)
}
