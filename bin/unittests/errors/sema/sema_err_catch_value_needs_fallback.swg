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

// A type with a default resumes with it; a discarded result, a written replacement and
// a handler that leaves are accepted for any type.
func catchFallbackAccepted()->s32
{
    discard catch catchFallbackPointer()
    let pointer  = catch catchFallbackPointer() orelse &catchFallbackStorage
    let leaving  = catch catchFallbackPointer() { return 0 }
    let captured = catch catchFallbackCount() orelse cast(s32, Swag.err != null)
    return pointer[] + leaving[] + captured + catch catchFallbackCount()
}
