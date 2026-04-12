#global fileprivate

struct ParamAffectTarget
{
    value: s32
}

impl ParamAffectTarget
{
    #[Swag.Overload]
    mtd opAffect(value: s32)
    {
        .value = value
    }

    #[Swag.Implicit, Swag.Overload]
    mtd opAffect(value: u16)
    {
        .value = cast(s32) value
    }
}

func takesValue(value: ParamAffectTarget)
{
}

#test
{
    takesValue(7'u16)
    takesValue(5's32) // swc-expected-error {{sema_err_cannot_cast}}
}
