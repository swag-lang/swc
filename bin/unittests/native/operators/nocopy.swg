#global private

// '#[Swag.NoCopy]' forbids copies but keeps moves and direct constructions legal.

var g_moves: s32
var g_drops: s32

#[Swag.NoCopy]
struct Handle
{
    x: s32
}

impl Handle
{
    mtd opPostMove() { g_moves += 1 }
    mtd opDrop() { if .x != 0 do g_drops += 1 }
}

func makeHandle(v: s32)->Handle
{
    var h = Handle{v}
    return h
}

// Moves and rvalue initializations are allowed.
#test
{
    g_moves, g_drops = 0

    var a = Handle{1}     // direct construction
    var b = #move a       // explicit move
    Swag.assert(b.x == 1)
    Swag.assert(g_moves == 1)

    var c: Handle
    c = #move b     // move assignment
    Swag.assert(c.x == 1)
    Swag.assert(g_moves == 2)

    var d = makeHandle(7)     // rvalue init from a call result
    Swag.assert(d.x == 7)
}

// A struct with 'opDrop' owns what that method releases, so it states no copy and is handed
// over with '#move'. Declaring 'opPostCopy' beside it opts the copy back in.
struct DropOnly
{
    x: s32
}

impl DropOnly
{
    mtd opDrop() {}
}

struct DropAndCopy
{
    x: s32
}

impl DropAndCopy
{
    mtd opDrop() {}
    mtd opPostCopy() {}
}

#test
{
    var a = DropOnly{5}
    var b = #move a
    Swag.assert(b.x == 5)
    var c: DropOnly
    c = #move b
    Swag.assert(c.x == 5)
}

#test
{
    var a = DropAndCopy{5}
    var b = a
    Swag.assert(b.x == 5)
    var c: DropAndCopy
    c = a
    Swag.assert(c.x == 5)
}
