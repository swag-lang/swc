#global fileprivate

struct GeneratedEqualsOnlyField
{
    value: s32
}

impl GeneratedEqualsOnlyField
{
    mtd const opEquals(other: const &GeneratedEqualsOnlyField)->bool
    {
        return .value == other.value
    }
}

#[Swag.Operators(opCompare)]
struct GeneratedNeedsFieldCompare
{
    field: GeneratedEqualsOnlyField // swc-expected-error {{sema_err_operator_generation_field_unsupported}}
}
