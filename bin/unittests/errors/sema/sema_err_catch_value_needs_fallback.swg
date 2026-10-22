#global private

func catchFallbackCount()->s32 fail
{
    return 1
}

func catchFallbackBare()->s32
{
    return catch catchFallbackCount()     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
}

func catchFallbackLet()
{
    let value = catch catchFallbackCount()     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
    discard value
}

func catchFallbackArgument(value: s32)
{
    discard value
}

func catchFallbackCall()
{
    catchFallbackArgument(catch catchFallbackCount())     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
}

// A discarded result, a capture, and an explicit fallback are all accepted.
func catchFallbackAccepted()->s32
{
    discard catch catchFallbackCount()
    let captured = catch catchFallbackCount() as err
    discard err
    return captured + (catch catchFallbackCount() else 0)
}
