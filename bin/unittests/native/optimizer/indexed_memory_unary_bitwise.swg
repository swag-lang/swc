#global private

#[Swag.NoInline]
func complement64(values: [*] u64, index: u64)
{
    values[index] = ~values[index]
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negate64(values: [*] s64, index: u64)
{
    values[index] = -values[index]
}

#[Swag.NoInline]
func complement32(values: [*] u32, index: u64)
{
    values[index] = ~values[index]
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negate8(values: [*] s8, index: u64)
{
    values[index] = -values[index]
}

#test
{
    var unsigned64: [4] u64 = [0, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    complement64(&unsigned64[0], 0)
    complement64(&unsigned64[0], 2)
    Swag.assert(unsigned64[0] == 0xFFFFFFFFFFFFFFFF and unsigned64[1] == 1 and unsigned64[2] == 0x7FFFFFFFFFFFFFFF and unsigned64[3] == 0xFFFFFFFFFFFFFFFF)

    var signed64: [4] s64 = [0, 1, -1, -9223372036854775808's64]
    negate64(&signed64[0], 1)
    negate64(&signed64[0], 3)
    Swag.assert(signed64[0] == 0 and signed64[1] == -1 and signed64[2] == -1 and signed64[3] == -9223372036854775808's64)

    var unsigned32: [4] u32 = [0, 1, 0x80000000, 0xFFFFFFFF]
    complement32(&unsigned32[0], 1)
    complement32(&unsigned32[0], 3)
    Swag.assert(unsigned32[0] == 0 and unsigned32[1] == 0xFFFFFFFE and unsigned32[2] == 0x80000000 and unsigned32[3] == 0)

    var signed8: [4] s8 = [0, 1, -1, -128's8]
    negate8(&signed8[0], 1)
    negate8(&signed8[0], 3)
    Swag.assert(signed8[0] == 0 and signed8[1] == -1 and signed8[2] == -1 and signed8[3] == -128's8)
}
