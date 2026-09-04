#global private

// 'Swag.Late' qualifies a struct field or a global variable (both have zero-initialized
// storage that serves as the 'unset' sentinel). A local or parameter has no such
// storage lifetime and must use '' definite assignment instead.

func lateLocal()
{
    #[Swag.Late]
    var value: *s32     // swc-expected-error {{sema_err_late_not_field}}
    Swag.print(value)
}

func lateParam( #[Swag.Late]
value: *s32)     // swc-expected-error {{sema_err_late_not_field}}
{
    Swag.print(value)
}
