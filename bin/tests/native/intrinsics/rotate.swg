#global fileprivate //

// ============================================================
// @rol — rotate left
// ============================================================

#[Swag.NoInline]
func rolU8(value: u8, count: u8)->u8 => @rol(value, count)

#[Swag.NoInline]
func rolU16(value: u16, count: u8)->u16 => @rol(value, count)

#[Swag.NoInline]
func rolU32(value: u32, count: u8)->u32 => @rol(value, count)

#[Swag.NoInline]
func rolU64(value: u64, count: u8)->u64 => @rol(value, count)

// u8
#test
{
    @assert(rolU8(0b00000001'u8, 0'u8) == 0b00000001'u8)
    @assert(rolU8(0b00000001'u8, 1'u8) == 0b00000010'u8)
    @assert(rolU8(0b00000001'u8, 4'u8) == 0b00010000'u8)
    @assert(rolU8(0b00000001'u8, 7'u8) == 0b10000000'u8)
    @assert(rolU8(0b10000000'u8, 1'u8) == 0b00000001'u8)
    @assert(rolU8(0b10110001'u8, 2'u8) == 0b11000110'u8)
    @assert(rolU8(0xFF'u8, 3'u8) == 0xFF'u8)
    @assert(rolU8(0'u8, 5'u8) == 0'u8)
}

// u16
#test
{
    @assert(rolU16(0x0001'u16, 0'u8) == 0x0001'u16)
    @assert(rolU16(0x0001'u16, 1'u8) == 0x0002'u16)
    @assert(rolU16(0x0001'u16, 8'u8) == 0x0100'u16)
    @assert(rolU16(0x0001'u16, 15'u8) == 0x8000'u16)
    @assert(rolU16(0x8000'u16, 1'u8) == 0x0001'u16)
    @assert(rolU16(0xFFFF'u16, 7'u8) == 0xFFFF'u16)
    @assert(rolU16(0'u16, 9'u8) == 0'u16)
    @assert(rolU16(0xA5A5'u16, 4'u8) == 0x5A5A'u16)
}

// u32
#test
{
    @assert(rolU32(1'u32, 0'u8) == 1'u32)
    @assert(rolU32(1'u32, 1'u8) == 2'u32)
    @assert(rolU32(1'u32, 16'u8) == 0x00010000'u32)
    @assert(rolU32(1'u32, 31'u8) == 0x80000000'u32)
    @assert(rolU32(0x80000000'u32, 1'u8) == 1'u32)
    @assert(rolU32(0xFFFFFFFF'u32, 13'u8) == 0xFFFFFFFF'u32)
    @assert(rolU32(0'u32, 10'u8) == 0'u32)
    @assert(rolU32(0x12345678'u32, 8'u8) == 0x34567812'u32)
    @assert(rolU32(0x12345678'u32, 16'u8) == 0x56781234'u32)
}

// u64
#test
{
    @assert(rolU64(1'u64, 0'u8) == 1'u64)
    @assert(rolU64(1'u64, 1'u8) == 2'u64)
    @assert(rolU64(1'u64, 32'u8) == 0x00000001_00000000'u64)
    @assert(rolU64(1'u64, 63'u8) == 0x80000000_00000000'u64)
    @assert(rolU64(0x80000000_00000000'u64, 1'u8) == 1'u64)
    @assert(rolU64(0xFFFFFFFF_FFFFFFFF'u64, 17'u8) == 0xFFFFFFFF_FFFFFFFF'u64)
    @assert(rolU64(0'u64, 33'u8) == 0'u64)
    @assert(rolU64(0x01234567_89ABCDEF'u64, 32'u8) == 0x89ABCDEF_01234567'u64)
}

// ============================================================
// @ror — rotate right
// ============================================================

#[Swag.NoInline]
func rorU8(value: u8, count: u8)->u8 => @ror(value, count)

#[Swag.NoInline]
func rorU16(value: u16, count: u8)->u16 => @ror(value, count)

#[Swag.NoInline]
func rorU32(value: u32, count: u8)->u32 => @ror(value, count)

#[Swag.NoInline]
func rorU64(value: u64, count: u8)->u64 => @ror(value, count)

// u8
#test
{
    @assert(rorU8(0b00000001'u8, 0'u8) == 0b00000001'u8)
    @assert(rorU8(0b00000001'u8, 1'u8) == 0b10000000'u8)
    @assert(rorU8(0b10000000'u8, 1'u8) == 0b01000000'u8)
    @assert(rorU8(0b10000000'u8, 7'u8) == 0b00000001'u8)
    @assert(rorU8(0b00000010'u8, 1'u8) == 0b00000001'u8)
    @assert(rorU8(0xFF'u8, 3'u8) == 0xFF'u8)
    @assert(rorU8(0'u8, 5'u8) == 0'u8)
    @assert(rorU8(0b11000110'u8, 2'u8) == 0b10110001'u8)
}

// u16
#test
{
    @assert(rorU16(0x0001'u16, 0'u8) == 0x0001'u16)
    @assert(rorU16(0x0001'u16, 1'u8) == 0x8000'u16)
    @assert(rorU16(0x8000'u16, 15'u8) == 0x0001'u16)
    @assert(rorU16(0x0100'u16, 8'u8) == 0x0001'u16)
    @assert(rorU16(0xFFFF'u16, 7'u8) == 0xFFFF'u16)
    @assert(rorU16(0'u16, 9'u8) == 0'u16)
    @assert(rorU16(0x5A5A'u16, 4'u8) == 0xA5A5'u16)
}

// u32
#test
{
    @assert(rorU32(1'u32, 0'u8) == 1'u32)
    @assert(rorU32(1'u32, 1'u8) == 0x80000000'u32)
    @assert(rorU32(0x80000000'u32, 31'u8) == 1'u32)
    @assert(rorU32(0x00010000'u32, 16'u8) == 1'u32)
    @assert(rorU32(0xFFFFFFFF'u32, 13'u8) == 0xFFFFFFFF'u32)
    @assert(rorU32(0'u32, 10'u8) == 0'u32)
    @assert(rorU32(0x12345678'u32, 8'u8) == 0x78123456'u32)
    @assert(rorU32(0x12345678'u32, 16'u8) == 0x56781234'u32)
}

// u64
#test
{
    @assert(rorU64(1'u64, 0'u8) == 1'u64)
    @assert(rorU64(1'u64, 1'u8) == 0x80000000_00000000'u64)
    @assert(rorU64(0x80000000_00000000'u64, 63'u8) == 1'u64)
    @assert(rorU64(0x00000001_00000000'u64, 32'u8) == 1'u64)
    @assert(rorU64(0xFFFFFFFF_FFFFFFFF'u64, 17'u8) == 0xFFFFFFFF_FFFFFFFF'u64)
    @assert(rorU64(0'u64, 33'u8) == 0'u64)
    @assert(rorU64(0x89ABCDEF_01234567'u64, 32'u8) == 0x01234567_89ABCDEF'u64)
}

// ============================================================
// @rol / @ror roundtrip: ror(rol(x, n), n) == x
// ============================================================

#test
{
    @assert(rorU8(rolU8(0xAB'u8, 3'u8), 3'u8) == 0xAB'u8)
    @assert(rorU16(rolU16(0x1234'u16, 7'u8), 7'u8) == 0x1234'u16)
    @assert(rorU32(rolU32(0xDEADBEEF'u32, 11'u8), 11'u8) == 0xDEADBEEF'u32)
    @assert(rorU64(rolU64(0xCAFEBABE_DEADBEEF'u64, 37'u8), 37'u8) == 0xCAFEBABE_DEADBEEF'u64)
}

// Full rotation returns original value
#test
{
    @assert(rolU8(0xAB'u8, 8'u8) == 0xAB'u8)
    @assert(rorU8(0xAB'u8, 8'u8) == 0xAB'u8)
    @assert(rolU16(0x1234'u16, 16'u8) == 0x1234'u16)
    @assert(rorU16(0x1234'u16, 16'u8) == 0x1234'u16)
    @assert(rolU32(0xDEADBEEF'u32, 32'u8) == 0xDEADBEEF'u32)
    @assert(rorU32(0xDEADBEEF'u32, 32'u8) == 0xDEADBEEF'u32)
    @assert(rolU64(0xCAFEBABE_DEADBEEF'u64, 64'u8) == 0xCAFEBABE_DEADBEEF'u64)
    @assert(rorU64(0xCAFEBABE_DEADBEEF'u64, 64'u8) == 0xCAFEBABE_DEADBEEF'u64)
}
