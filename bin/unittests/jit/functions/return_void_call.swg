#global private

var gReturnVoidCallValue: s32 = 0

func markReturnVoidCall(value: s32)
{
    gReturnVoidCallValue = value
}

#[Swag.Warning("sema_warn_unreachable_code", .Disable)]
func shortcutImplicitReturnVoidCall()
{
    return markReturnVoidCall(1)
    gReturnVoidCallValue = 99
}

#[Swag.Warning("sema_warn_unreachable_code", .Disable)]
func shortcutExplicitReturnVoidCall()->void
{
    return markReturnVoidCall(2)
    gReturnVoidCallValue = 99
}

#test
{
    gReturnVoidCallValue = 0
    shortcutImplicitReturnVoidCall()
    @assert(gReturnVoidCallValue == 1)

    gReturnVoidCallValue = 0
    shortcutExplicitReturnVoidCall()
    @assert(gReturnVoidCallValue == 2)
}
