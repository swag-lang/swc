#global fileprivate

#[Swag.Operators(opBinary)] // swc-expected-error {{sema_err_operator_attribute_invalid_operator}}
struct InvalidGeneratedOperator
{
    value: s32
}
