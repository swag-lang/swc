#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func add64(values: [*] u64, index: u64)->u64 => values[index] + values[index + 1]

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtract64(values: [*] u64, index: u64)->u64 => values[index] - values[index + 1]

#[Swag.NoInline]
func and32(values: [*] u32, index: u64)->u32 => values[index] & values[index + 1]

#[Swag.NoInline]
func or16(values: [*] u16, index: u64)->u16 => values[index] | values[index + 1]

#[Swag.NoInline]
func xor8(values: [*] u8, index: u64)->u8 => values[index] ^ values[index + 1]

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func multiply64(values: [*] s64, index: u64)->s64 => values[index] * values[index + 1]

#test
{
    var values64 = [0x123456789ABCDEF0'u64, 0x1111111111111111, 0xFEDCBA9876543210]
    Swag.assert(add64(&values64[0], 0) == 0x23456789ABCDF001)
    Swag.assert(subtract64(&values64[0], 1) == 0x123456789ABCDF01)

    var values32 = [0xFFFF00FF'u32, 0x0FF0FFFF]
    var values16 = [0xA50F'u16, 0x0FF0]
    var values8  = [0xA5'u8, 0x3C]
    Swag.assert(and32(&values32[0], 0) == 0x0FF000FF)
    Swag.assert(or16(&values16[0], 0) == 0xAFFF)
    Swag.assert(xor8(&values8[0], 0) == 0x99)

    var signedValues = [-7's64, 9]
    Swag.assert(multiply64(&signedValues[0], 0) == -63)
}
