#global fileprivate

#[Swag.Operators(opEquals)] // swc-expected-error {{sema_err_operator_generation_duplicate}}
struct(T) DuplicateGeneratedGenericEquals
{
    value: T
}

impl DuplicateGeneratedGenericEquals
{
    mtd const opEquals(other: const &DuplicateGeneratedGenericEquals)->bool
    {
        return .value == other.value
    }
}

var trigger: DuplicateGeneratedGenericEquals's32
