#global private

#[Swag.NoInline]
func combined64(a, b, c: u64)->u64 => ((a ^ b) + (a & c)) ^ (b / (c | 1))

#[Swag.NoInline]
func combined32(a, b, c: u32)->u32 => ((a ^ b) + (a & c)) ^ (b / (c | 1))

#[Swag.NoInline]
func shifted(a, count: u64)->u64 => (a << (count & 63)) ^ (a >> (count & 63)) ^ count

#test
{
    Swag.assert(combined64(0x0, 0x1, 0x0) == 0x0)
    Swag.assert(combined32(0x0, 0x1, 0x0) == 0x0)
    Swag.assert(shifted(0x0, 0x1) == 0x1)
    Swag.assert(combined64(0x1, 0x0, 0x1) == 0x2)
    Swag.assert(combined32(0x1, 0x0, 0x1) == 0x2)
    Swag.assert(shifted(0x1, 0x0) == 0x0)
    Swag.assert(combined64(0xFFFFFFFF, 0x80000000, 0x1F) == 0x8421085C)
    Swag.assert(combined32(0xFFFFFFFF, 0x80000000, 0x1F) == 0x8421085C)
    Swag.assert(shifted(0xFFFFFFFF, 0x80000000) == 0x80000000)
    Swag.assert(combined64(0xFFFFFFFFFFFFFFFF, 0x7, 0x3F) == 0x37)
    Swag.assert(combined32(0xFFFFFFFF, 0x7, 0x3F) == 0x37)
    Swag.assert(shifted(0xFFFFFFFFFFFFFFFF, 0x7) == 0xFE00000000000078)
    Swag.assert(combined64(0x123456789ABCDEF0, 0x13579BDF, 0x55555555) == 0x1234567899FF997F)
    Swag.assert(combined32(0x9ABCDEF0, 0x13579BDF, 0x55555555) == 0x99FF997F)
    Swag.assert(shifted(0x123456789ABCDEF0, 0x13579BDF) == 0x4D5E6F78373F372E)
}
