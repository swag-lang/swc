#global private

func infallible()->s32 => 42

#test
{
    let value = assume infallible()     // swc-expected-error {{sema_err_error_mgmt_operand_not_fallible}}
}

#test
{
    let value = assume 42     // swc-expected-error {{sema_err_error_mgmt_operand_not_fallible}}
}

func nullableResult()->*s32? fail { return null }

#test
{
    let value: *s32 = assume nullableResult()     // swc-expected-error {{sema_err_cannot_cast}}
}
