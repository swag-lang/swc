#global fileprivate

// Declaring a name that shadows a function parameter is flagged.
func shadowed1(value: s32)
{
    if true
    {
        var value = 1                // swc-expected-error {{sema_err_ghosting}}
    }
}

func shadowed2(count: s32)
{
    for count
    {
        var count = true             // swc-expected-error {{sema_err_ghosting}}
    }
}
