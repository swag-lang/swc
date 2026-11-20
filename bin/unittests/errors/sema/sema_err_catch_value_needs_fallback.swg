#global private

var catchFallbackStorage: s32 = 1

func catchFallbackCount()->s32 fail
{
    return 1
}

func catchFallbackPointer()->*s32 fail
{
    return &catchFallbackStorage
}

func catchFallbackNullable()->string? fail
{
    return null
}

func catchFallbackWithoutValue() fail
{
    fail Swag.BaseError{"test failure"}
}

// A non-null pointer has no default value, so a read failure needs its replacement.
func catchFallbackBare()->*s32
{
    return catch (catchFallbackPointer()     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
                  )
}

func catchFallbackLet()
{
    let value = catch (catchFallbackPointer()     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
                       )
    discard value
}

func catchFallbackArgument(value: *s32)
{
    discard value
}

func catchFallbackCall()
{
    catchFallbackArgument(catch catchFallbackPointer())     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
}

func catchFallbackBareScalar()->s32
{
    return catch catchFallbackCount()     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
}

func catchFallbackBareNullable()->string?
{
    return catch catchFallbackNullable()     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
}

func catchFallbackOwnerStillNeedsValue()->s32
{
    var saved: Swag.Error
    let value = catch catchFallbackCount() as saved     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
    discard saved
    return value
}

// Discard, a written replacement and an exiting handler cover their respective paths.
func catchFallbackAccepted()->s32
{
    discard catch catchFallbackPointer()
    var owner: Swag.Error
    discard catch catchFallbackCount() as owner
    catch catchFallbackWithoutValue() as owner
    let pointer  = catch catchFallbackPointer() orelse &catchFallbackStorage
    let leaving  = catch catchFallbackPointer() { return 0 }
    let captured = catch catchFallbackCount() orelse cast(s32, Swag.err != null)
    return pointer[] + leaving[] + captured + catch catchFallbackCount() orelse 0
}
