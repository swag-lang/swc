#global private

// The field initializer calls code whose pointer stride needs this same unfinished layout.
#[Swag.NoInline]
func advance(value: [*] Item)->[*] Item => value + 1

func initialValue(value: [*] Item?)->s64
{
    if value
    {
        return cast(s64, advance(value))
    }
    return 17
}

struct Item     // swc-expected-error {{sema_err_cyclic_dependency}}
{
    value: s64 = #run initialValue(null)
    tail:  [5] u32
}
