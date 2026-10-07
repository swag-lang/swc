#global private

#[Swag.DynCast]
struct UnhandledCastBase {}
struct UnhandledCastChild { using base: UnhandledCastBase }

func missingCastHandler(value: *UnhandledCastBase)->*UnhandledCastChild
{
    return cast(*UnhandledCastChild, value)     // swc-expected-error {{sema_err_fallible_cast_requires_handler}}
}

func missingPresenceHandler(value: *s32?)->*s32
{
    return cast(*s32, value)     // swc-expected-error {{sema_err_fallible_cast_requires_handler}}
}
