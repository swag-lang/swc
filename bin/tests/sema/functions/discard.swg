#global fileprivate

func mustUse()->s32
{
    return 1
}

#[Swag.Discardable]
func canDiscard()->s32
{
    return 2
}

#test
{
    mustUse() // swc-expected-error {{sema_err_return_value_must_be_used}}
}

#test
{
    let v = mustUse()
    @assert(v == 1)
}

#test
{
    discard mustUse()
}

#test
{
    canDiscard()
}
