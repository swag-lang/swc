#global fileprivate

struct MissingGenericEqualsField
{
    value: s32
}

#[Swag.Operators(opEquals)]
struct(T) GeneratedGenericNeedsFieldEquals
{
    field: T // swc-expected-error {{sema_err_operator_generation_field_unsupported}}
}

var trigger: GeneratedGenericNeedsFieldEquals'MissingGenericEqualsField
