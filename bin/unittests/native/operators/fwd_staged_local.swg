#global private

// A local initialized from a '#fwd' parameter in its move variant takes the caller's object:
// that object must be reset, exactly as an assignment from the same parameter resets it, or the
// caller would drop a value the local now owns.

var g_copies: s32
var g_moves:  s32
var g_drops:  s32

struct Owned
{
    id: s32
}

impl Owned
{
    mtd opPostCopy() { g_copies += 1 }
    mtd opPostMove() { g_moves += 1 }
    mtd opDrop()
    {
        if .id do
            g_drops += 1
    }
}

func initFrom(dst: *Owned, v: #fwd Owned)
{
    var local: Owned = #fwd v
    dst[] = #nodrop #move local
}

func initFromThenRead(dst: *Owned, v: #fwd Owned)->s32
{
    var local: Owned = #fwd v
    let left         = v.id
    dst[] = #nodrop #move local
    return left
}

func assignFrom(dst: *Owned, v: #fwd Owned)
{
    var local: Owned
    local = #fwd v
    dst[] = #nodrop #move local
}

#test
{
    var source = Owned{1}
    var target: Owned
    initFrom(&target, #move source)
    Swag.assert(target.id == 1)
    Swag.assert(source.id == 0)
}

#test
{
    var source = Owned{2}
    var target: Owned
    Swag.assert(initFromThenRead(&target, #move source) == 0)
    Swag.assert(target.id == 2 and source.id == 0)
}

#test
{
    var source = Owned{3}
    var target: Owned
    assignFrom(&target, #move source)
    Swag.assert(target.id == 3 and source.id == 0)
}

// The copy variant leaves the caller's object alone.
#test
{
    var source = Owned{4}
    var target: Owned
    initFrom(&target, source)
    Swag.assert(target.id == 4 and source.id == 4)
}
