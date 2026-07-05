#global private

var g_copies: s32
var g_moves:  s32

struct Tracked
{
    x: s32
}

impl Tracked
{
    mtd opPostCopy() { g_copies += 1 }
    mtd opPostMove() { g_moves += 1 }
    mtd opDrop() {}
}

var g_slot: Tracked

func store(v: #fwd Tracked)
{
    g_slot = #nodrop #fwd v
}

func storeVia(v: #fwd Tracked)
{
    store(#fwd v)
}

// '#fwd' parameter: calling without '#move' selects the copy variant.
#test
{
    g_copies, g_moves = 0
    var t = Tracked{10}
    store(t)
    @assert(g_slot.x == 10)
    @assert(g_copies == 1)
    @assert(g_moves == 0)
    @assert(t.x == 10) // source untouched
}

// '#fwd' parameter: calling with '#move' selects the move variant.
#test
{
    g_copies, g_moves = 0
    var t = Tracked{20}
    store(#move t)
    @assert(g_slot.x == 20)
    @assert(g_copies == 0)
    @assert(g_moves == 1)
}

// '#fwd' in a call argument forwards the passing mode through a call chain.
#test
{
    g_copies, g_moves = 0
    var t = Tracked{30}
    storeVia(t)
    @assert(g_slot.x == 30)
    @assert(g_copies == 1)
    @assert(g_moves == 0)

    g_copies, g_moves = 0
    var u = Tracked{40}
    storeVia(#move u)
    @assert(g_slot.x == 40)
    @assert(g_copies == 0)
    @assert(g_moves == 1)
}

struct(T) Box
{
    value: T
}

impl Box
{
    mtd put(v: #fwd T)
    {
        .value = #fwd v
    }
}

// '#fwd' parameter on a method of a generic struct.
#test
{
    g_copies, g_moves = 0
    var b: Box'Tracked
    var t = Tracked{50}
    b.put(t)
    @assert(b.value.x == 50)
    @assert(g_copies == 1)

    var u = Tracked{60}
    b.put(#move u)
    @assert(b.value.x == 60)
    @assert(g_moves == 1)
}

var g_a: Tracked
var g_b: Tracked

func storeBoth(a: #fwd Tracked, b: #fwd Tracked)
{
    g_a = #nodrop #fwd a
    g_b = #nodrop #fwd b
}

// A mixed call (one plain, one '#move' argument) selects the copy variant (exact match
// on the plain argument), and the '#move' argument is still honored: its source is
// moved into a call-site temporary that the parameter borrows, then consumed.
#test
{
    g_copies, g_moves = 0
    var t = Tracked{80}
    var u = Tracked{81}
    storeBoth(t, #move u)
    @assert(g_a.x == 80)
    @assert(g_b.x == 81)
    @assert(g_copies == 2) // both parameters are copied by the body
    @assert(g_moves == 1)  // the '#move' argument moved into its temporary
    @assert(t.x == 80)     // plain argument untouched
    @assert(u.x == 0)      // '#move' argument honored: source reset to defaults
}

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

func storeMoveOnly(v: #fwd MoveOnly)
{
    g_moveOnly = #nodrop #fwd v
}

// A non-copyable type can still use the move variant of a '#fwd' function.
#test
{
    var m = MoveOnly{70}
    storeMoveOnly(#move m)
    @assert(g_moveOnly.x == 70)
}
