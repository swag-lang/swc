#global private

// Drop elision: when the source of a '#move' is a plain local that is provably never
// used again (no read/write after the move, no address escape, move not inside a
// branch or loop below the declaration), the compiler elides both the reset of the
// source and its scope-exit drop: 'opDrop' is NOT called on the reset value.

var DropCount: u32 = 0
var DropTrace: s64 = 0
var g_sink: s32   = 0
var g_cond        = true

func resetHooks()
{
    DropCount = 0
    DropTrace = 0
}

struct Tracked
{
    value: s32 = 5
}

impl Tracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }

    mtd opPostMove()
    {
        .value += 20
    }
}

// The source is dead after the move: its reset and scope drop are elided.
#test
{
    resetHooks()
    {
        var src = Tracked{3}
        var dst = Tracked{7}
        dst = #move src
    }
    // Drops: 'dst' as assignment target (7), 'dst' at scope exit (3+20). 'src': elided.
    @assert(DropCount == 2)
    @assert(DropTrace == 723)
}

// A read after the move keeps the documented reset semantics: no elision.
#test
{
    resetHooks()
    {
        var src = Tracked{3}
        var dst = Tracked{7}
        dst = #move src
        g_sink = src.value
    }
    @assert(g_sink == 5) // reset to defaults
    @assert(DropCount == 3)
    @assert(DropTrace == 72305)
}

// A move inside a branch does not post-dominate the scope exit: no elision.
#test
{
    resetHooks()
    {
        var src = Tracked{3}
        var dst = Tracked{7}
        if g_cond do
            dst = #move src
    }
    @assert(DropCount == 3)
    @assert(DropTrace == 72305)
}

// A taken address can outlive the move: no elision.
#test
{
    resetHooks()
    {
        var src = Tracked{3}
        var dst = Tracked{7}
        let p = &src
        g_sink = p.value
        dst = #move src
    }
    @assert(g_sink == 3)
    @assert(DropCount == 3)
    @assert(DropTrace == 72305)
}

// A move inside a loop below the declaration re-reads the source next iteration: no elision.
#test
{
    resetHooks()
    {
        var src = Tracked{3}
        var dst = Tracked{7}
        for var i = 0; i < 1; i += 1 do
            dst = #nodrop #move src
    }
    @assert(DropCount == 2)
    @assert(DropTrace == 2305)
}

// Elision also applies to the 'var a = #move b' initialization form.
#test
{
    resetHooks()
    {
        var src = Tracked{3}
        var dst = #move src
        g_sink = dst.value
    }
    @assert(g_sink == 23)
    @assert(DropCount == 1)
    @assert(DropTrace == 23)
}

// Only the LAST move of a chain elides: the first one keeps the reset semantics.
#test
{
    resetHooks()
    {
        var src = Tracked{3}
        var d1  = Tracked{6}
        var d2  = Tracked{7}
        d1 = #move src
        d2 = #move src // moves the reset value (5); 'src' then elided
    }
    // Drops: d1 target (6), d2 target (7), scope: d2 (5+20), d1 (3+20). src: elided.
    @assert(DropCount == 4)
    @assert(DropTrace == 6072523)
}
