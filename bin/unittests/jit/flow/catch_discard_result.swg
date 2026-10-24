#global private

var CatchDiscardTarget: s32 = 42
var CatchDiscardDrops:  s32

struct CatchDiscardOwner
{
    target: *s32
    marker: s32 = 23
}

impl CatchDiscardOwner
{
    mtd opDrop()
    {
        Swag.assert(.target == &CatchDiscardTarget and .marker == 23)
        CatchDiscardDrops += 1
    }
}

#[Swag.NoInline]
func catchDiscardOwner(succeeds: bool)->CatchDiscardOwner fail
{
    if not succeeds do
        fail 7
    return {target: &CatchDiscardTarget}
}

#[Swag.Inline]
func inlineCatchDiscardOwner(succeeds: bool)->CatchDiscardOwner fail
{
    return try catchDiscardOwner(succeeds)
}

#test
{
    CatchDiscardDrops = 0
    discard catch catchDiscardOwner(false)
    Swag.assert(CatchDiscardDrops == 0)
    discard catch catchDiscardOwner(true)
    Swag.assert(CatchDiscardDrops == 1)
    discard catch inlineCatchDiscardOwner(false)
    Swag.assert(CatchDiscardDrops == 1)
    discard catch inlineCatchDiscardOwner(true)
    Swag.assert(CatchDiscardDrops == 2)
    discard catch catchDiscardOwner(false) orelse expect catchDiscardOwner(true)
    Swag.assert(CatchDiscardDrops == 3)
}

// Register-sized owners need an address for their destructor too.
struct CatchDiscardSmallOwner
{
    target: *s32
}

impl CatchDiscardSmallOwner
{
    mtd opDrop()
    {
        Swag.assert(.target == &CatchDiscardTarget)
        CatchDiscardDrops += 1
    }
}

#[Swag.NoInline]
func catchDiscardSmallOwner(succeeds: bool)->CatchDiscardSmallOwner fail
{
    if not succeeds do fail 7
    return {target: &CatchDiscardTarget}
}

#test
{
    let before = CatchDiscardDrops
    discard catch catchDiscardSmallOwner(false)
    Swag.assert(CatchDiscardDrops == before)
    discard catch catchDiscardSmallOwner(true)
    Swag.assert(CatchDiscardDrops == before + 1)
    discard catch catchDiscardSmallOwner(false) orelse expect catchDiscardSmallOwner(true)
    Swag.assert(CatchDiscardDrops == before + 2)
}
