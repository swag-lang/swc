#global private

func failDeferredCapture() fail
{
    fail 7
}

func captureIsNotVisibleBeforeDefer()
{
    discard error     // swc-expected-error {{sema_err_unknown_symbol}}
    defer catch failDeferredCapture() do discard Swag.err
}

func captureIsNotVisibleAfterDefer()
{
    defer catch failDeferredCapture() do discard Swag.err
    discard error     // swc-expected-error {{sema_err_unknown_symbol}}
}
