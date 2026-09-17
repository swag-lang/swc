#global private

#[Swag.NoInline] func outside32(x, low, high: u32)->u32 => x < low or x > high ? 1 : 0
#[Swag.NoInline] func both32(a, b, c, d: u32)->u32 => a < b and c != d ? 1 : 0
#[Swag.NoInline] func either64(a, b, c, d: u64)->u64 => a == b or c > d ? 1 : 0
#[Swag.NoInline] func different32(a, b, c, d: u32)->u32 => (a < b) != (c < d) ? 1 : 0

#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values do for b in values do for c in values do for d in values
    {
        Swag.assert(either64(a, b, c, d) == (a == b or c > d ? 1 : 0))

        let a32 = cast #wrap (u32) a
        let b32 = cast #wrap (u32) b
        let c32 = cast #wrap (u32) c
        let d32 = cast #wrap (u32) d
        Swag.assert(outside32(a32, b32, c32) == (a32 < b32 or a32 > c32 ? 1 : 0))
        Swag.assert(both32(a32, b32, c32, d32) == (a32 < b32 and c32 != d32 ? 1 : 0))
        Swag.assert(different32(a32, b32, c32, d32) == ((a32 < b32) != (c32 < d32) ? 1 : 0))
    }
}
