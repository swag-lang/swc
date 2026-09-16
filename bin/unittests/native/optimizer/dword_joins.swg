#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A 32-bit value merged from several paths reaches its 64-bit reader with its
// upper half clear; a value that took a 64-bit path must still be cut. A
// boolean widened on one path only is read as a byte after the join.

#[Swag.Optimize(true), Swag.NoInline]
func fnv(p: const [*] u8, n: u64)->u32
{
    var h = 2166136261'u32
    for i in n
    {
        h ^= cast(u32) p[i]
        h *= 16777619
    }
    return h
}

#[Swag.Optimize(true), Swag.NoInline]
func pick(big: u64, flag: bool)->u64
{
    var v = big
    if flag do v = cast(u64) (cast(u32) (big * 3))
    return cast(u64) (cast(u32) v)
}

#[Swag.Optimize(true), Swag.NoInline]
func isPow2(x: u64)->bool => x != 0 and (x & (x - 1)) == 0

#test
{
    var bytes: [5] u8 = [104, 101, 108, 108, 111]
    Swag.assert(fnv(&bytes[0], 5) == 0x4F9F2CAB)
    Swag.assert(fnv(&bytes[0], 0) == 2166136261)
    Swag.assert(pick(0x100000005, false) == 5)
    Swag.assert(pick(0x100000005, true) == 15)
    Swag.assert(isPow2(1) and isPow2(0x8000000000000000))
    Swag.assert(not isPow2(0) and not isPow2(6))
}
