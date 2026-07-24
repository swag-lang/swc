#global private

// '#late' qualifies a struct field or a global variable (both have zero-initialized
// storage that serves as the 'unset' sentinel). A local or parameter has no such
// storage lifetime and must use '= undefined' definite assignment instead.

func lateLocal()
{
    var value: #late *s32     // swc-expected-error {{sema_err_late_not_field}}
    @print(value)
}

func lateParam(value: #late *s32)     // swc-expected-error {{sema_err_late_not_field}}
{
    @print(value)
}
