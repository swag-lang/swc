#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func rotated(a, b: u64)->u64 => (a << (b & 63)) | (a >> ((0 - b) & 63))
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func liveCount(a, b: u64)->u64 => ((a << (b & 63)) | (a >> ((0 - b) & 63))) ^ b
#[Swag.NoInline]
func selfShift(a: u64)->u64 => a << (a & 63)
#[Swag.NoInline]
func sharedCount(a, b: u64)->u64 => (a << (b & 63)) ^ b
#[Swag.NoInline]
func dynamicShift(a, b: u64)->u64 => a << b
#[Swag.NoInline]
func shifted32(a, b: u32)->u32 => a << (b & 31)

#test
{
    let values = [0'u64, 1, 31, 63, 64, 0xFFFFFFFF, 0x100000001, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.assert(selfShift(a) == dynamicShift(a, a & 63))
        for b in values
        {
            Swag.assert(liveCount(a, b) == (rotated(a, b) ^ b))
            Swag.assert(sharedCount(a, b) == (dynamicShift(a, b & 63) ^ b))
            let lowA = cast(u32) (a & 0xFFFFFFFF)
            let lowB = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(shifted32(lowA, lowB) == cast(u32) (dynamicShift(lowA, b & 31) & 0xFFFFFFFF))
        }
    }
}
