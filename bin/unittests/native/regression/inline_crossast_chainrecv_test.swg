#global fileprivate

struct Holder
{
    slab: InlineChain.Slab'InlineChain.Cell
}

impl Holder
{
    // Chained inline receiver whose base `.slab` is a method auto-member.
    mtd probe(i: u64)->bool
    {
        return .slab[i].isOn()
    }

    // Same chain, but the inlined element method mutates through the reference: verifies the
    // materialized receiver aliases the real storage (not a copy).
    mtd activate(i: u64)
    {
        .slab[i].turnOn()
    }
}

// Same chain off a plain local (no method auto-member): the always-working baseline.
func probeLocal(i: u64)->bool
{
    var s: InlineChain.Slab'InlineChain.Cell
    return s[i].isOn()
}

#test
{
    var h: Holder
    @assert(!h.probe(2))
    h.activate(2)
    @assert(h.probe(2))
    @assert(h.slab.cells[2].n == 10)
    @assert(!h.probe(0))
    @assert(!h.probe(1))
    @assert(!probeLocal(0))
}
