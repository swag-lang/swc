#global fileprivate

#[Swag.Operators(opEquals)] // swc-expected-error {{sema_err_operator_generation_duplicate}}
struct DuplicateGeneratedEquals
{
    value: s32
}

impl DuplicateGeneratedEquals
{
    mtd const opEquals(other: const &DuplicateGeneratedEquals)->bool
    {
        return .value == other.value
    }
}
