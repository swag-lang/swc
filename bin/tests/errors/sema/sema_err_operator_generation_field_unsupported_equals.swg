#global fileprivate

struct MissingGeneratedEqualsField
{
    value: s32
}

#[Swag.Operators(opEquals)]
struct GeneratedNeedsFieldEquals
{
    field: MissingGeneratedEqualsField // swc-expected-error {{sema_err_operator_generation_field_unsupported}}
}
