// A fallible function returns through caller-provided storage, so its return runs the
// value's lifecycle hooks. 'return local' and 'return #move local' must both transfer
// ownership — one move, no copy, no drop of the moved-out local — whatever mix of
// 'try' initializers and defers the function holds.

var MoveCopies: s32
var MoveMoves:  s32
var MoveDrops:  s32

// Wider than a register so the value keeps address semantics and its hooks.
struct MovePayload
{
    data:  [16] u8
    value: s32
}

impl MovePayload
{
    mtd opPostCopy()
    {
        MoveCopies += 1
    }

    mtd opPostMove()
    {
        MoveMoves += 1
    }

    mtd opDrop()
    {
        MoveDrops += 1
    }
}

func produceMovePayload(seed: s32)->MovePayload fail
{
    var r: MovePayload
    r.value = seed * 3
    return r
}

func forwardBare(seed: s32)->MovePayload fail
{
    var result = #move try produceMovePayload(seed)
    return result
}

func forwardMove(seed: s32)->MovePayload fail
{
    var result = #move try produceMovePayload(seed)
    return #move result
}

func forwardMoveDefer(seed: s32)->MovePayload fail
{
    var guard = 0
    defer guard += 1
    var result = #move try produceMovePayload(seed)
    return #move result
}

// 'return #move local' transfers ownership exactly like the bare local
#test
{
    MoveCopies, MoveMoves, MoveDrops = 0
    let a = catch forwardBare(Seed)
    check(a.value == Seed * 3, 60)
    let bareCopies = MoveCopies

    MoveCopies, MoveMoves, MoveDrops = 0
    let b = catch forwardMove(Seed)
    check(b.value == Seed * 3, 61)
    check(MoveCopies == bareCopies, 62)

    MoveCopies, MoveMoves, MoveDrops = 0
    let c = catch forwardMoveDefer(Seed)
    check(c.value == Seed * 3, 63)
    check(MoveCopies == bareCopies, 64)

    Swag.assert(a.value == b.value and b.value == c.value)
}
