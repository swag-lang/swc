#global private

// A '#fwd' parameter on an interface method declares two slots (copy and move variants);
// an implementation using '#fwd' provides both, and calls through the interface value
// dispatch to the right variant.

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

interface IStore
{
    mtd set(v: #fwd Tracked);
}

struct Store
{
    value: Tracked
}

impl IStore for Store
{
    mtd impl set(v: #fwd Tracked)
    {
        .value = #fwd v
    }
}

#test
{
    var s: Store
    var i = cast(IStore) s

    g_copies, g_moves = 0
    var t = Tracked{1}
    i.set(t) // copy slot
    @assert(s.value.x == 1)
    @assert(g_copies == 1)
    @assert(g_moves == 0)

    var u = Tracked{2}
    i.set(#move u) // move slot
    @assert(s.value.x == 2)
    @assert(g_moves == 1)
}

// A single '#move' interface method accepts both call styles through the interface
// value: a plain argument is copied into a call-site temporary.
interface ISink
{
    mtd sink(v: #move Tracked);
}

struct Sink
{
    value: Tracked
}

impl ISink for Sink
{
    mtd impl sink(v: #move Tracked)
    {
        .value = #nodrop #move v
    }
}

#test
{
    var s: Sink
    var i = cast(ISink) s

    g_copies, g_moves = 0
    var t = Tracked{3}
    i.sink(t) // copy call style: temp copy + move
    @assert(s.value.x == 3)
    @assert(t.x == 3) // source untouched
    @assert(g_copies == 1)
    @assert(g_moves == 1)

    var u = Tracked{4}
    i.sink(#move u) // move call style
    @assert(s.value.x == 4)
    @assert(g_moves == 2)
}
