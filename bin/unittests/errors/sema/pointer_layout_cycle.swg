#global private

// The field initializer calls code whose pointer stride needs this same unfinished layout.
// swc-expected-error@(+2,+11) {{sema_err_cyclic_dependency}}
#[Swag.NoInline]
func advance(value: [*] Item)->[*] Item => value + 1

func initialValue(value: [*] Item?)->s64
{
    if value do
        return cast(s64) advance(value)
    return 17
}

struct Item
{
    value: s64 = #run initialValue(null)
    tail: [5] u32
}
