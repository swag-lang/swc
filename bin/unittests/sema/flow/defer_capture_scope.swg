#global private

func failDeferredCapture() fail
{
    fail 7
}

func captureIsNotVisibleBeforeDefer()
{
    discard error     // swc-expected-error {{sema_err_unknown_symbol}}
    defer catch failDeferredCapture() as error else do discard error
}

func captureIsNotVisibleAfterDefer()
{
    defer catch failDeferredCapture() as error else do discard error
    discard error     // swc-expected-error {{sema_err_unknown_symbol}}
}
