#global private

// `notnull` asserts a value is not null; `assume` is error management only.
// Each keyword rejects the other's role.

struct NotNullOperandNode { value: s32 }

func notNullOperandPlain()->s32 { return 42 }

#test
{
    // `notnull` on a type is not a value expression.
    let bad = notnull NotNullOperandNode // swc-expected-error {{sema_err_not_value_expr}}
}

#test
{
    // `assume` no longer unwraps nullability: a plain nullable value is not throwable.
    var storage: NotNullOperandNode
    var p: #null *NotNullOperandNode = &storage
    let q = assume p // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
}

#test
{
    // `assume` on a call to a non-throwable function stays an error too.
    let v = assume notNullOperandPlain() // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
}
