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

    var a = Handle{1}      // direct construction
    var b = #move a        // explicit move
    @assert(b.x == 1)
    @assert(g_moves == 1)

    var c: Handle
    c = #move b            // move assignment
    @assert(c.x == 1)
    @assert(g_moves == 2)

    var d = makeHandle(7)  // rvalue init from a call result
    @assert(d.x == 7)
}

// A struct with 'opDrop' but no 'opPostCopy' remains copyable ('opPostCopy' only
// customizes the copy; only '#[Swag.NoCopy]' forbids it).
struct DropOnly
{
    x: s32
}

impl DropOnly
{
    mtd opDrop() {}
}

#test
{
    var a = DropOnly{5}
    var b = a
    @assert(b.x == 5)
    var c: DropOnly
    c = a
    @assert(c.x == 5)
}
