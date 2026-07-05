#global private

// A '#move' parameter accepts a plain (copyable) value: the caller materializes a
// temporary deep copy at the call site and passes it as the move reference. The
// temporary is dropped right after the call, which is a no-op when the callee
// consumed it.

var g_copies: s32
var g_moves:  s32
var g_drops:  s32

struct Tracked
{
    x: s32
}

impl Tracked
{
    mtd opPostCopy() { g_copies += 1 }
    mtd opPostMove() { g_moves += 1 }
    mtd opDrop() { if .x != 0 do g_drops += 1 }
}

var g_slot: Tracked

func sink(v: #move Tracked)
{
    g_slot = #nodrop #move v
}

// A sink that does NOT always consume its parameter.
func sinkIf(cond: bool, v: #move Tracked)
{
    if cond do
        g_slot = #nodrop #move v
}

// Copy call style: implicit temporary copy, source untouched.
#test
{
    g_copies, g_moves, g_drops = 0
    var a = Tracked{1}
    sink(a)
    @assert(g_slot.x == 1)
    @assert(a.x == 1)
    @assert(g_copies == 1)
    @assert(g_moves == 1)
    @assert(g_drops == 0) // temp consumed: drop is a no-op
}

// Move call style: unchanged, zero cost.
#test
{
    g_copies, g_moves, g_drops = 0
    var b = Tracked{2}
    sink(#move b)
    @assert(g_slot.x == 2)
    @assert(g_copies == 0)
    @assert(g_moves == 1)
}

// Callee does not consume: the live temporary is dropped by the caller.
#test
{
    g_copies, g_moves, g_drops = 0
    var c = Tracked{3}
    sinkIf(false, c)
    @assert(g_copies == 1)
    @assert(g_moves == 0)
    @assert(g_drops == 1)
    @assert(c.x == 3)
}

// Loop: each iteration has its own temporary lifetime.
#test
{
    g_copies, g_moves, g_drops = 0
    var d = Tracked{4}
    for var i = 0; i < 4; i += 1
    {
        sinkIf((i & 1) == 0, d)
    }
    @assert(g_copies == 4)
    @assert(g_moves == 2)
    @assert(g_drops == 2)
}

// Through a function value: one signature, both call styles.
#test
{
    g_copies, g_moves, g_drops = 0
    let f: func(v: #move Tracked) = &sink
    var e = Tracked{5}
    f(e)
    @assert(g_slot.x == 5)
    @assert(g_copies == 1)
    @assert(g_moves == 1)

    var h = Tracked{6}
    f(#move h)
    @assert(g_slot.x == 6)
    @assert(g_moves == 2)
}

// The '#fwd' copy variant (exact match) wins over copy-to-move on the move variant.
func storeFwd(v: #fwd Tracked)
{
    g_slot = #nodrop #fwd v
}

#test
{
    g_copies, g_moves, g_drops = 0
    var a = Tracked{7}
    storeFwd(a)
    @assert(g_slot.x == 7)
    @assert(g_copies == 1)
    @assert(g_moves == 0) // no temporary: the dedicated copy variant was selected
}

// Non-copyable types keep working through an explicit '#move'.
#[Swag.NoCopy]
struct MoveOnly
{
    x: s32
}

impl MoveOnly
{
    mtd opDrop() {}
    mtd opPostMove() {}
}

var g_moveOnly: MoveOnly

func sinkMoveOnly(v: #move MoveOnly)
{
    g_moveOnly = #nodrop #move v
}

#test
{
    var m = MoveOnly{8}
    sinkMoveOnly(#move m)
    @assert(g_moveOnly.x == 8)
}

// Copy-to-move also works for scalar types: a plain scalar variable binds a
// '#move' scalar parameter through a call-site temporary.
var g_scalar: s32

func sinkScalar(v: #move s32)
{
    g_scalar = v
}

#test
{
    g_scalar = 0
    var n = 42
    sinkScalar(n)
    @assert(g_scalar == 42)
    @assert(n == 42) // source untouched

    var p = 43
    sinkScalar(#move p)
    @assert(g_scalar == 43)
}

enum Color { Red, Green, Blue }

var g_color: Color = .Red

func sinkColor(v: #move Color)
{
    g_color = v
}

#test
{
    var c = Color.Blue
    sinkColor(c)
    @assert(g_color == .Blue)
    sinkColor(#move c)
    @assert(g_color == .Blue)
}
