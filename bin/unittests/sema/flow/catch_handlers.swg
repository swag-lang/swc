#global private

func scopedCatchValue()->s32 fail
{
    fail 7
}

// 'Swag.err' exists only in a 'catch' handler or replacement.
func errOutsideHandler()
{
    discard catch scopedCatchValue()
    discard Swag.err     // swc-expected-error {{sema_err_unknown_symbol}}
}

func handlerCannotFallThrough()
{
    var handled = false
    let value   = catch scopedCatchValue() { handled = true }     // swc-expected-error {{sema_err_catch_handler_needs_exit}}
    discard value, handled
}

func captureDoesNotLeak()
{
    discard catch scopedCatchValue() orelse doNotKeep(Swag.err)
    discard Swag.err     // swc-expected-error {{sema_err_unknown_symbol}}
}

func doNotKeep(error: any?)->s32
{
    discard error
    return 0
}

// A persistent capture keeps the error; the read result resumes with its default value.
func persistentCaptureResumesWithDefault()
{
    var owner: Swag.Error
    let value = catch scopedCatchValue() as owner
    discard value
}

func persistentCaptureNeedsErrorOwner()
{
    var value: s32
    discard catch scopedCatchValue() as value     // swc-expected-error {{sema_err_catch_owner_not_error_variable}}
}
