#global private     //

#[Swag.Strict]
alias RotateStrictU32 = u32

#[Swag.Strict]
alias RotateStrictU8  = u8

// ============================================================
// Swag.rol — rotate left
// ============================================================

#[Swag.NoInline]
func rolU8(value: u8, count: u8)->u8 => Swag.rol(value, count)

#[Swag.NoInline]
func rolU16(value: u16, count: u8)->u16 => Swag.rol(value, count)

#[Swag.NoInline]
func rolU32(value: u32, count: u8)->u32 => Swag.rol(value, count)

#[Swag.NoInline]
func rolU64(value: u64, count: u8)->u64 => Swag.rol(value, count)

#[Swag.NoInline]
func rolStrictU32(value: RotateStrictU32, count: RotateStrictU8)->RotateStrictU32 => Swag.rol(value, count)

// u8
#test
{
    Swag.require(rolU8(0b00000001_u8, 0_u8) == 0b00000001_u8)
    Swag.require(rolU8(0b00000001_u8, 1_u8) == 0b00000010_u8)
    Swag.require(rolU8(0b00000001_u8, 4_u8) == 0b00010000_u8)
    Swag.require(rolU8(0b00000001_u8, 7_u8) == 0b10000000_u8)
    Swag.require(rolU8(0b10000000_u8, 1_u8) == 0b00000001_u8)
    Swag.require(rolU8(0b10110001_u8, 2_u8) == 0b11000110_u8)
    Swag.require(rolU8(0xFF_u8, 3_u8) == 0xFF_u8)
    Swag.require(rolU8(0_u8, 5_u8) == 0_u8)
}

// u16
#test
{
    Swag.require(rolU16(0x0001_u16, 0_u8) == 0x0001_u16)
    Swag.require(rolU16(0x0001_u16, 1_u8) == 0x0002_u16)
    Swag.require(rolU16(0x0001_u16, 8_u8) == 0x0100_u16)
    Swag.require(rolU16(0x0001_u16, 15_u8) == 0x8000_u16)
    Swag.require(rolU16(0x8000_u16, 1_u8) == 0x0001_u16)
    Swag.require(rolU16(0xFFFF_u16, 7_u8) == 0xFFFF_u16)
    Swag.require(rolU16(0_u16, 9_u8) == 0_u16)
    Swag.require(rolU16(0xA5A5_u16, 4_u8) == 0x5A5A_u16)
}

// u32
#test
{
    Swag.require(rolU32(1_u32, 0_u8) == 1_u32)
    Swag.require(rolU32(1_u32, 1_u8) == 2_u32)
    Swag.require(rolU32(1_u32, 16_u8) == 0x00010000_u32)
    Swag.require(rolU32(1_u32, 31_u8) == 0x80000000_u32)
    Swag.require(rolU32(0x80000000_u32, 1_u8) == 1_u32)
    Swag.require(rolU32(0xFFFFFFFF_u32, 13_u8) == 0xFFFFFFFF_u32)
    Swag.require(rolU32(0_u32, 10_u8) == 0_u32)
    Swag.require(rolU32(0x12345678_u32, 8_u8) == 0x34567812_u32)
    Swag.require(rolU32(0x12345678_u32, 16_u8) == 0x56781234_u32)
}

// u64
#test
{
    Swag.require(rolU64(1_u64, 0_u8) == 1_u64)
    Swag.require(rolU64(1_u64, 1_u8) == 2_u64)
    Swag.require(rolU64(1_u64, 32_u8) == 0x00000001_00000000_u64)
    Swag.require(rolU64(1_u64, 63_u8) == 0x80000000_00000000_u64)
    Swag.require(rolU64(0x80000000_00000000_u64, 1_u8) == 1_u64)
    Swag.require(rolU64(0xFFFFFFFF_FFFFFFFF_u64, 17_u8) == 0xFFFFFFFF_FFFFFFFF_u64)
    Swag.require(rolU64(0_u64, 33_u8) == 0_u64)
    Swag.require(rolU64(0x01234567_89ABCDEF_u64, 32_u8) == 0x89ABCDEF_01234567_u64)
}

// ============================================================
// Swag.ror — rotate right
// ============================================================

#[Swag.NoInline]
func rorU8(value: u8, count: u8)->u8 => Swag.ror(value, count)

#[Swag.NoInline]
func rorU16(value: u16, count: u8)->u16 => Swag.ror(value, count)

#[Swag.NoInline]
func rorU32(value: u32, count: u8)->u32 => Swag.ror(value, count)

#[Swag.NoInline]
func rorU64(value: u64, count: u8)->u64 => Swag.ror(value, count)

#[Swag.NoInline]
func rorStrictU32(value: RotateStrictU32, count: RotateStrictU8)->RotateStrictU32 => Swag.ror(value, count)

// u8
#test
{
    Swag.require(rorU8(0b00000001_u8, 0_u8) == 0b00000001_u8)
    Swag.require(rorU8(0b00000001_u8, 1_u8) == 0b10000000_u8)
    Swag.require(rorU8(0b10000000_u8, 1_u8) == 0b01000000_u8)
    Swag.require(rorU8(0b10000000_u8, 7_u8) == 0b00000001_u8)
    Swag.require(rorU8(0b00000010_u8, 1_u8) == 0b00000001_u8)
    Swag.require(rorU8(0xFF_u8, 3_u8) == 0xFF_u8)
    Swag.require(rorU8(0_u8, 5_u8) == 0_u8)
    Swag.require(rorU8(0b11000110_u8, 2_u8) == 0b10110001_u8)
}

// u16
#test
{
    Swag.require(rorU16(0x0001_u16, 0_u8) == 0x0001_u16)
    Swag.require(rorU16(0x0001_u16, 1_u8) == 0x8000_u16)
    Swag.require(rorU16(0x8000_u16, 15_u8) == 0x0001_u16)
    Swag.require(rorU16(0x0100_u16, 8_u8) == 0x0001_u16)
    Swag.require(rorU16(0xFFFF_u16, 7_u8) == 0xFFFF_u16)
    Swag.require(rorU16(0_u16, 9_u8) == 0_u16)
    Swag.require(rorU16(0x5A5A_u16, 4_u8) == 0xA5A5_u16)
}

// u32
#test
{
    Swag.require(rorU32(1_u32, 0_u8) == 1_u32)
    Swag.require(rorU32(1_u32, 1_u8) == 0x80000000_u32)
    Swag.require(rorU32(0x80000000_u32, 31_u8) == 1_u32)
    Swag.require(rorU32(0x00010000_u32, 16_u8) == 1_u32)
    Swag.require(rorU32(0xFFFFFFFF_u32, 13_u8) == 0xFFFFFFFF_u32)
    Swag.require(rorU32(0_u32, 10_u8) == 0_u32)
    Swag.require(rorU32(0x12345678_u32, 8_u8) == 0x78123456_u32)
    Swag.require(rorU32(0x12345678_u32, 16_u8) == 0x56781234_u32)
}

// u64
#test
{
    Swag.require(rorU64(1_u64, 0_u8) == 1_u64)
    Swag.require(rorU64(1_u64, 1_u8) == 0x80000000_00000000_u64)
    Swag.require(rorU64(0x80000000_00000000_u64, 63_u8) == 1_u64)
    Swag.require(rorU64(0x00000001_00000000_u64, 32_u8) == 1_u64)
    Swag.require(rorU64(0xFFFFFFFF_FFFFFFFF_u64, 17_u8) == 0xFFFFFFFF_FFFFFFFF_u64)
    Swag.require(rorU64(0_u64, 33_u8) == 0_u64)
    Swag.require(rorU64(0x89ABCDEF_01234567_u64, 32_u8) == 0x01234567_89ABCDEF_u64)
}

// ============================================================
// Swag.rol / Swag.ror roundtrip: ror(rol(x, n), n) == x
// ============================================================

#test
{
    Swag.require(rorU8(rolU8(0xAB_u8, 3_u8), 3_u8) == 0xAB_u8)
    Swag.require(rorU16(rolU16(0x1234_u16, 7_u8), 7_u8) == 0x1234_u16)
    Swag.require(rorU32(rolU32(0xDEADBEEF_u32, 11_u8), 11_u8) == 0xDEADBEEF_u32)
    Swag.require(rorU64(rolU64(0xCAFEBABE_DEADBEEF_u64, 37_u8), 37_u8) == 0xCAFEBABE_DEADBEEF_u64)
}

// Full rotation returns original value
#test
{
    Swag.require(rolU8(0xAB_u8, 8_u8) == 0xAB_u8)
    Swag.require(rorU8(0xAB_u8, 8_u8) == 0xAB_u8)
    Swag.require(rolU16(0x1234_u16, 16_u8) == 0x1234_u16)
    Swag.require(rorU16(0x1234_u16, 16_u8) == 0x1234_u16)
    Swag.require(rolU32(0xDEADBEEF_u32, 32_u8) == 0xDEADBEEF_u32)
    Swag.require(rorU32(0xDEADBEEF_u32, 32_u8) == 0xDEADBEEF_u32)
    Swag.require(rolU64(0xCAFEBABE_DEADBEEF_u64, 64_u8) == 0xCAFEBABE_DEADBEEF_u64)
    Swag.require(rorU64(0xCAFEBABE_DEADBEEF_u64, 64_u8) == 0xCAFEBABE_DEADBEEF_u64)
}

// Strict aliases
#test
{
    const a = Swag.rol(cast(RotateStrictU32, 0x12345678_u32), cast(RotateStrictU8, 8))
    const b = Swag.ror(cast(RotateStrictU32, 0x12345678_u32), cast(RotateStrictU8, 8))

    #assert(#typeof(a) == RotateStrictU32)
    #assert(#typeof(b) == RotateStrictU32)

    Swag.require(a == cast(RotateStrictU32, 0x34567812_u32))
    Swag.require(b == cast(RotateStrictU32, 0x78123456_u32))
}

#test
{
    let a = rolStrictU32(cast(RotateStrictU32, 0x80000001_u32), cast(RotateStrictU8, 1))
    let b = rorStrictU32(cast(RotateStrictU32, 0x80000001_u32), cast(RotateStrictU8, 1))

    #assert(#typeof(a) == RotateStrictU32)
    #assert(#typeof(b) == RotateStrictU32)

    Swag.require(a == cast(RotateStrictU32, 0x00000003_u32))
    Swag.require(b == cast(RotateStrictU32, 0xC0000000_u32))
}
