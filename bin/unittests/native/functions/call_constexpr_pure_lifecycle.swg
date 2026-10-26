#global private

// A body whose values run lifecycle hooks calls code no call node shows: a local's 'opDrop'
// at scope exit here. Such a function is not pure, so a call with constant arguments still
// runs, and so do its hooks.
var PureLifecycleDrops: s32

struct PureLifecycleToken
{
    id: s32
}

impl PureLifecycleToken
{
    mtd opDrop()
    {
        PureLifecycleDrops += 1
    }
}

#[Swag.NoInline]
func pureLifecycleChoose(other: bool)->PureLifecycleToken
{
    var result: retval = PureLifecycleToken{id: 1}
    if other do
        return PureLifecycleToken{id: 2}
    return result
}

#[Swag.NoInline]
func pureLifecycleReplaced()->PureLifecycleToken
{
    var token = PureLifecycleToken{id: 1}
    return PureLifecycleToken{id: 2}
}

// The first call makes this caller wait, so the purity of the second callee is already
// known when its call is analyzed: that is when a pure call would be folded.
#[Swag.NoInline]
func pureLifecycleCaller()->s32
{
    PureLifecycleDrops = 0
    scope
    {
        let token = pureLifecycleChoose(true)
        Swag.assert(token.id == 2)
    }

    Swag.assert(PureLifecycleDrops == 2)
    PureLifecycleDrops = 0
    scope
    {
        let token = pureLifecycleReplaced()
        Swag.assert(token.id == 2)
    }

    return PureLifecycleDrops
}

#test
{
    Swag.assert(pureLifecycleCaller() == 2)
}
