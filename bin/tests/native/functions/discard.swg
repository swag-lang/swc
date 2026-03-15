#global fileprivate // swc-option suite-test

var gMustUseCalls: s32
var gCanDiscardCalls: s32
func mustUse()->s32
{
    gMustUseCalls += 1
    return 1
}

#[Swag.Discardable]
func canDiscard()->s32
{
    gCanDiscardCalls += 1
    return 2
}


#test
{
    gMustUseCalls = 0
    let v = mustUse()
    @assert(v == 1)
    @assert(gMustUseCalls == 1)
}

#test
{
    gMustUseCalls = 0
    discard mustUse()
    @assert(gMustUseCalls == 1)
}

#test
{
    gCanDiscardCalls = 0
    canDiscard()
    @assert(gCanDiscardCalls == 1)
}
