#global fileprivate

struct ExplicitOnlyCast
{
    value: s32
}

impl ExplicitOnlyCast
{
    #[Swag.Overload]
    mtd const opCast() -> s32
    {
        return .value
    }
}

func takesValue(value: s32)
{
}

#test
{
    let value = ExplicitOnlyCast{value: 7}
    takesValue(value) // swc-expected-error {{sema_err_cannot_cast}}
}
