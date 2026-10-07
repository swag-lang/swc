#global private

func increment(value: *u32, amount: u32)
{
    value[] += amount
}

#[Swag.NoInline]
func functionAddress()->const *void => cast(const *void, &increment)

#[Swag.NoInline]
func forwardedFunctionAddress()->const *void => functionAddress()

struct CallbackAddress
{
    address: const *void
}

#[Swag.NoInline]
func wrappedFunctionAddress()->CallbackAddress => {cast(const *void, &increment)}

#[Swag.NoInline]
func invokeDeferred(value: *u32)
{
    let action = cast(func(*u32, u32), functionAddress())
    action(value, 3)
    defer action(value, 7)
}

// The address must belong to the loaded executable, including when it is hidden in
// an aggregate or returned through another otherwise constant-foldable function.
#test
{
    var value = 0'u32
    invokeDeferred(&value)
    Swag.assert(value == 10)

    let forwarded = cast(func(*u32, u32), forwardedFunctionAddress())
    forwarded(&value, 5)
    Swag.assert(value == 15)

    let wrapped = wrappedFunctionAddress()
    let action  = cast(func(*u32, u32), wrapped.address)
    action(&value, 9)
    Swag.assert(value == 24)
}
