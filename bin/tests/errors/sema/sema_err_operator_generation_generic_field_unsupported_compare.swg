#global fileprivate

struct GeneratedGenericEqualsOnlyField
{
    value: s32
}

impl GeneratedGenericEqualsOnlyField
{
    mtd const opEquals(other: const &GeneratedGenericEqualsOnlyField)->bool
    {
        return .value == other.value
    }
}

#[Swag.Operators(opCompare)]
struct(T) GeneratedGenericNeedsFieldCompare
{
    field: T // swc-expected-error {{sema_err_operator_generation_field_unsupported}}
}

var trigger: GeneratedGenericNeedsFieldCompare'GeneratedGenericEqualsOnlyField
