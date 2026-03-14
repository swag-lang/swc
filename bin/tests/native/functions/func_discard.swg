#global fileprivate // swc-option suite-test

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
