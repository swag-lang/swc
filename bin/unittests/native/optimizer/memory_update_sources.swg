#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A value copied only to be stored or added into memory is taken from the
// register it was copied from. Byte and word stores keep their width, and a
// value still read after the store keeps its copy.

struct Counters
{
    hits:  s32
    total: s64
    flags: u8
    kind:  u16
}

#[Swag.Optimize(true), Swag.NoInline]
func bump(c: *Counters, hits: s32, total: s64)
{
    c.hits += hits
    c.total += total
}

#[Swag.Optimize(true), Swag.NoInline]
func tag(c: *Counters, flags: u8, kind: u16)
{
    c.flags = flags
    c.kind = kind
}

#[Swag.Optimize(true), Swag.NoInline]
func bumpAndReturn(c: *Counters, hits: s32)->s32
{
    c.hits -= hits
    return hits * 2
}

#test
{
    var c: Counters
    bump(&c, -3, 0x100000000)
    bump(&c, 5, -1)
    Swag.assert(c.hits == 2 and c.total == 0xFFFFFFFF)
    tag(&c, 0xAB, 0xFFFF)
    Swag.assert(c.flags == 0xAB and c.kind == 0xFFFF and c.hits == 2)
    Swag.assert(bumpAndReturn(&c, 7) == 14 and c.hits == -5)
}
