#global private

// A lifecycle intrinsic needs the pointed-to struct's completed operator registrations.
func repair(value: *Item?)
{
    if value
    {
        Swag.postCopy(value)
    }
}

func initialValue()->s64
{
    repair(null)
    return 17
}

struct Item     // swc-expected-error {{sema_err_cyclic_dependency}}
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
