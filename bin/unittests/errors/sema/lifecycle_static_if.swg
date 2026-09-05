#global private

struct(T) Gated
{
    value: T
}

impl Gated
{
    #static if T == s32
    {
        mtd opPostCopy() {}
    }
}

#test
{
    var value: Gated'u32
    value.opPostCopy()     // swc-expected-error {{sema_err_unknown_symbol}}
}

struct(Enabled: bool) Switched
{
    value: s32
}

impl Switched
{
    #static switch Enabled
    {
    case true:
        mtd opPostCopy() {}
    case false:
        mtd reset() {}
    }
}

#test
{
    var value: Switched'(false)
    value.opPostCopy()     // swc-expected-error {{sema_err_unknown_symbol}}
}
