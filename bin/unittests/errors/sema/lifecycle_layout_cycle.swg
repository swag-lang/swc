#global private

// A lifecycle intrinsic needs the pointed-to struct's completed operator registrations.
// swc-expected-error@(+1,+13) {{sema_err_cyclic_dependency}}
func repair(value: *Item?)
{
    if value do
        Swag.postCopy(value)
}

func initialValue()->s64
{
    repair(null)
    return 17
}

struct Item
{
    value: s64 = #run initialValue()
}

impl Item
{
    mtd opPostCopy()
    {
        .value += 1
    }
}
