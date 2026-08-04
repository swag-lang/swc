#global private

// The postfix `!` asserts a value is not null; `expect` is error management only.
// Each rejects the other's role.

struct NotNullOperandNode { value: s32 }

func notNullOperandPlain()->s32 { return 42 }

#test
{
    // `!` on a type is not a value expression.
    let bad = NotNullOperandNode!     // swc-expected-error {{sema_err_not_value_expr}}
}

#test
{
    // `expect` no longer unwraps nullability: a plain nullable value is not fallible.
    var storage: NotNullOperandNode
    var p:       #null *NotNullOperandNode = &storage
    let q                                  = expect p     // swc-expected-error {{sema_err_error_mgmt_operand_not_fallible}}
}

#test
{
    // `expect` on a call to a non-fallible function stays an error too.
    let v = expect notNullOperandPlain()     // swc-expected-error {{sema_err_error_mgmt_operand_not_fallible}}
}
