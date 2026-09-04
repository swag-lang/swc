#global private

// A call reached through '?.' keeps its short circuit whatever the inline mode: the
// receiver's null test must skip the whole call, and the fallback must be produced.

struct OptGuardNode
{
    value: s32
}

impl OptGuardNode
{
    mtd bump()->s32
    {
        .value += 1
        return .value
    }

    // Touches no member, so a skipped null guard would run it silently.
    mtd seven()->s32 => 7

    mtd reset()
    {
        .value = 0
    }
}

var g_optGuardNode: OptGuardNode

func optGuardGet(use: bool)->*OptGuardNode?
{
    if use do
        return &g_optGuardNode
    return null
}

// A null receiver takes the fallback, and the method body never runs.
#test
{
    Swag.assert((optGuardGet(false)?.seven() orelse -1) == -1)
    Swag.assert((optGuardGet(true)?.seven() orelse -1) == 7)
}

// The guarded call mutates through the receiver only on the non-null path.
#test
{
    g_optGuardNode.value = 42
    Swag.assert((optGuardGet(true)?.bump() orelse -1) == 43)
    Swag.assert((optGuardGet(false)?.bump() orelse -1) == -1)
    Swag.assert(g_optGuardNode.value == 43)
}

// A void guarded call is a statement that does nothing when the receiver is null.
#test
{
    g_optGuardNode.value = 5
    optGuardGet(false)?.reset()
    Swag.assert(g_optGuardNode.value == 5)
    optGuardGet(true)?.reset()
    Swag.assert(g_optGuardNode.value == 0)
}
