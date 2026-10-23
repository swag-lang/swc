#global private

func scopedCatchValue()->s32 fail
{
    fail 7
}

func captureNeedsHandler()
{
    discard catch scopedCatchValue() as error     // swc-expected-error {{sema_err_catch_capture_needs_handler}}
}

func valueNeedsReplacement()
{
    let value = catch scopedCatchValue() as error     // swc-expected-error {{sema_err_catch_capture_needs_handler}}
    discard value
}

func handlerCannotFallThrough()
{
    var handled = false
    let value   = catch scopedCatchValue() else { handled = true }     // swc-expected-error {{sema_err_catch_handler_needs_exit}}
    discard value, handled
}

func captureDoesNotLeak()
{
    discard catch scopedCatchValue() as error else doNotKeep(error)
    discard error     // swc-expected-error {{sema_err_unknown_symbol}}
}

func doNotKeep(error: any?)->s32
{
    discard error
    return 0
}

func persistentCaptureStillNeedsReplacement()
{
    var owner: Swag.Error
    let value = catch scopedCatchValue() as &owner     // swc-expected-error {{sema_err_catch_value_needs_fallback}}
    discard value
}

func persistentCaptureNeedsErrorOwner()
{
    var value: s32
    discard catch scopedCatchValue() as &value     // swc-expected-error {{sema_err_cannot_cast}}
}
