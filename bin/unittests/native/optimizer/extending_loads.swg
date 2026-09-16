#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A load read only through a widening becomes one extending load. Negative
// fields, byte and word widths, and a load with a second reader must keep
// their values.

struct Record
{
    tag:   u8
    kind:  s8
    count: u16
    delta: s16
    pad:   u16
    value: s32
    size:  u32
}

#[Swag.Optimize(true), Swag.NoInline]
func weighted(r: const *Record)->s64 => cast(s64) r.value * cast(s64) r.delta

#[Swag.Optimize(true), Swag.NoInline]
func unsignedSum(r: const *Record)->u64 => cast(u64) r.tag + cast(u64) r.count + cast(u64) r.size

#[Swag.Optimize(true), Swag.NoInline]
func signedByte(r: const *Record)->s32 => cast(s32) r.kind * 3

#[Swag.Optimize(true), Swag.NoInline]
func sharedLoad(r: const *Record)->s64
{
    let v = r.value
    return cast(s64) v + cast(s64) (v & 0xFF)
}

#test
{
    var r: Record = {tag: 0xF0, kind: -3, count: 0xFFFF, delta: -2, pad: 0, value: -7, size: 0xFFFFFFFF}
    Swag.assert(weighted(&r) == 14)
    Swag.assert(unsignedSum(&r) == 0xF0 + 0xFFFF + 0xFFFFFFFF)
    Swag.assert(signedByte(&r) == -9)
    Swag.assert(sharedLoad(&r) == 242)
}
