#global private     //

#[Swag.Strict]
alias BitCountStrictU32 = u32

// ============================================================
// Swag.countOnes — population count (number of set bits)
// ============================================================

#[Swag.NoInline]
func nzU8(value: u8)->u8 => Swag.countOnes(value)

#[Swag.NoInline]
func nzU16(value: u16)->u16 => Swag.countOnes(value)

#[Swag.NoInline]
func nzU32(value: u32)->u32 => Swag.countOnes(value)

#[Swag.NoInline]
func nzU64(value: u64)->u64 => Swag.countOnes(value)

#[Swag.NoInline]
func nzStrictU32(value: BitCountStrictU32)->BitCountStrictU32 => Swag.countOnes(value)

// Compile-time — nz
#test
{
    const a: u8 = Swag.countOnes(0_u8)
    const b: u8 = Swag.countOnes(0xFF_u8)
    const c: u8 = Swag.countOnes(0b10110000_u8)
    #assert(a == 0_u8)
    #assert(b == 8_u8)
    #assert(c == 3_u8)

    const d: u16 = Swag.countOnes(0_u16)
    const e: u16 = Swag.countOnes(0xFFFF_u16)
    const f: u16 = Swag.countOnes(0xF0F0_u16)
    #assert(d == 0_u16)
    #assert(e == 16_u16)
    #assert(f == 8_u16)

    const g: u32 = Swag.countOnes(0_u32)
    const h: u32 = Swag.countOnes(0xFFFFFFFF_u32)
    const i: u32 = Swag.countOnes(0x55555555_u32)
    #assert(g == 0_u32)
    #assert(h == 32_u32)
    #assert(i == 16_u32)

    const j: u64 = Swag.countOnes(0_u64)
    const k: u64 = Swag.countOnes(0xFFFFFFFF_FFFFFFFF_u64)
    const l: u64 = Swag.countOnes(0xF0000000_0000000F_u64)
    #assert(j == 0_u64)
    #assert(k == 64_u64)
    #assert(l == 8_u64)
}

// u8
#test
{
    Swag.require(nzU8(0_u8) == 0)
    Swag.require(nzU8(0xFF_u8) == 8)
    Swag.require(nzU8(0b10110000_u8) == 3)
    Swag.require(nzU8(0b01010101_u8) == 4)
    Swag.require(nzU8(0b10101010_u8) == 4)
    Swag.require(nzU8(1_u8) == 1)
    Swag.require(nzU8(0x80_u8) == 1)
}

// u16
#test
{
    Swag.require(nzU16(0_u16) == 0)
    Swag.require(nzU16(0xFFFF_u16) == 16)
    Swag.require(nzU16(0xF0F0_u16) == 8)
    Swag.require(nzU16(0x0001_u16) == 1)
    Swag.require(nzU16(0x8000_u16) == 1)
    Swag.require(nzU16(0x5555_u16) == 8)
}

// u32
#test
{
    Swag.require(nzU32(0_u32) == 0)
    Swag.require(nzU32(0xFFFFFFFF_u32) == 32)
    Swag.require(nzU32(0xFFFF0001_u32) == 17)
    Swag.require(nzU32(0x80000000_u32) == 1)
    Swag.require(nzU32(1_u32) == 1)
    Swag.require(nzU32(0x55555555_u32) == 16)
    Swag.require(nzU32(0xAAAAAAAA_u32) == 16)
}

// u64
#test
{
    Swag.require(nzU64(0_u64) == 0)
    Swag.require(nzU64(0xFFFFFFFF_FFFFFFFF_u64) == 64)
    Swag.require(nzU64(0xF0000000_0000000F_u64) == 8)
    Swag.require(nzU64(1_u64) == 1)
    Swag.require(nzU64(0x80000000_00000000_u64) == 1)
    Swag.require(nzU64(0x55555555_55555555_u64) == 32)
}

// ============================================================
// Swag.trailingZeros — count trailing zeros
// ============================================================

#[Swag.NoInline]
func tzU8(value: u8)->u8 => Swag.trailingZeros(value)

#[Swag.NoInline]
func tzU16(value: u16)->u16 => Swag.trailingZeros(value)

#[Swag.NoInline]
func tzU32(value: u32)->u32 => Swag.trailingZeros(value)

#[Swag.NoInline]
func tzU64(value: u64)->u64 => Swag.trailingZeros(value)

#[Swag.NoInline]
func tzStrictU32(value: BitCountStrictU32)->BitCountStrictU32 => Swag.trailingZeros(value)

// Compile-time — tz
#test
{
    const a: u8 = Swag.trailingZeros(0_u8)
    const b: u8 = Swag.trailingZeros(1_u8)
    const c: u8 = Swag.trailingZeros(0x80_u8)
    #assert(a == 8_u8)
    #assert(b == 0_u8)
    #assert(c == 7_u8)

    const d: u16 = Swag.trailingZeros(0_u16)
    const e: u16 = Swag.trailingZeros(0x8000_u16)
    #assert(d == 16_u16)
    #assert(e == 15_u16)

    const f: u32 = Swag.trailingZeros(0_u32)
    const g: u32 = Swag.trailingZeros(0x80000000_u32)
    #assert(f == 32_u32)
    #assert(g == 31_u32)

    const h: u64 = Swag.trailingZeros(0_u64)
    const i: u64 = Swag.trailingZeros(0x80000000_00000000_u64)
    #assert(h == 64_u64)
    #assert(i == 63_u64)
}

// u8
#test
{
    Swag.require(tzU8(0_u8) == 8)
    Swag.require(tzU8(1_u8) == 0)
    Swag.require(tzU8(0x80_u8) == 7)
    Swag.require(tzU8(0x28_u8) == 3)
    Swag.require(tzU8(0xFF_u8) == 0)
    Swag.require(tzU8(0b00010000_u8) == 4)
}

// u16
#test
{
    Swag.require(tzU16(0_u16) == 16)
    Swag.require(tzU16(1_u16) == 0)
    Swag.require(tzU16(0x8000_u16) == 15)
    Swag.require(tzU16(0xFFFF_u16) == 0)
    Swag.require(tzU16(0x0100_u16) == 8)
}

// u32
#test
{
    Swag.require(tzU32(0_u32) == 32)
    Swag.require(tzU32(1_u32) == 0)
    Swag.require(tzU32(0x80000000_u32) == 31)
    Swag.require(tzU32(0xFFFFFFFF_u32) == 0)
    Swag.require(tzU32(0x00010000_u32) == 16)
}

// u64
#test
{
    Swag.require(tzU64(0_u64) == 64)
    Swag.require(tzU64(1_u64) == 0)
    Swag.require(tzU64(0x80000000_00000000_u64) == 63)
    Swag.require(tzU64(0xFFFFFFFF_FFFFFFFF_u64) == 0)
    Swag.require(tzU64(0x00010000_00000000_u64) == 48)
}

// ============================================================
// Swag.leadingZeros — count leading zeros
// ============================================================

#[Swag.NoInline]
func lzU8(value: u8)->u8 => Swag.leadingZeros(value)

#[Swag.NoInline]
func lzU16(value: u16)->u16 => Swag.leadingZeros(value)

#[Swag.NoInline]
func lzU32(value: u32)->u32 => Swag.leadingZeros(value)

#[Swag.NoInline]
func lzU64(value: u64)->u64 => Swag.leadingZeros(value)

#[Swag.NoInline]
func lzStrictU32(value: BitCountStrictU32)->BitCountStrictU32 => Swag.leadingZeros(value)

// Compile-time — lz
#test
{
    const a: u8 = Swag.leadingZeros(0_u8)
    const b: u8 = Swag.leadingZeros(1_u8)
    const c: u8 = Swag.leadingZeros(0x80_u8)
    #assert(a == 8_u8)
    #assert(b == 7_u8)
    #assert(c == 0_u8)

    const d: u16 = Swag.leadingZeros(0_u16)
    const e: u16 = Swag.leadingZeros(1_u16)
    const f: u16 = Swag.leadingZeros(0x8000_u16)
    #assert(d == 16_u16)
    #assert(e == 15_u16)
    #assert(f == 0_u16)

    const g: u32 = Swag.leadingZeros(0_u32)
    const h: u32 = Swag.leadingZeros(1_u32)
    const i: u32 = Swag.leadingZeros(0x80000000_u32)
    #assert(g == 32_u32)
    #assert(h == 31_u32)
    #assert(i == 0_u32)

    const j: u64 = Swag.leadingZeros(0_u64)
    const k: u64 = Swag.leadingZeros(1_u64)
    const l: u64 = Swag.leadingZeros(0x80000000_00000000_u64)
    #assert(j == 64_u64)
    #assert(k == 63_u64)
    #assert(l == 0_u64)
}

// u8
#test
{
    Swag.require(lzU8(0_u8) == 8)
    Swag.require(lzU8(1_u8) == 7)
    Swag.require(lzU8(0x80_u8) == 0)
    Swag.require(lzU8(0xFF_u8) == 0)
    Swag.require(lzU8(0x0F_u8) == 4)
    Swag.require(lzU8(0x40_u8) == 1)
}

// u16
#test
{
    Swag.require(lzU16(0_u16) == 16)
    Swag.require(lzU16(1_u16) == 15)
    Swag.require(lzU16(0x8000_u16) == 0)
    Swag.require(lzU16(0xFFFF_u16) == 0)
    Swag.require(lzU16(0x00FF_u16) == 8)
}

// u32
#test
{
    Swag.require(lzU32(0_u32) == 32)
    Swag.require(lzU32(1_u32) == 31)
    Swag.require(lzU32(0x80000000_u32) == 0)
    Swag.require(lzU32(0xFFFFFFFF_u32) == 0)
    Swag.require(lzU32(0x0000FFFF_u32) == 16)
}

// u64
#test
{
    Swag.require(lzU64(0_u64) == 64)
    Swag.require(lzU64(1_u64) == 63)
    Swag.require(lzU64(0x80000000_00000000_u64) == 0)
    Swag.require(lzU64(0xFFFFFFFF_FFFFFFFF_u64) == 0)
    Swag.require(lzU64(0x00000000_FFFFFFFF_u64) == 32)
}

// ============================================================
// Cross-intrinsic consistency: single-bit patterns
// ============================================================

#test
{
    Swag.require(nzU8(0x01_u8) == 1)
    Swag.require(lzU8(0x01_u8) == 7)
    Swag.require(tzU8(0x01_u8) == 0)

    Swag.require(nzU8(0x80_u8) == 1)
    Swag.require(lzU8(0x80_u8) == 0)
    Swag.require(tzU8(0x80_u8) == 7)

    Swag.require(nzU32(0x00008000_u32) == 1)
    Swag.require(lzU32(0x00008000_u32) == 16)
    Swag.require(tzU32(0x00008000_u32) == 15)
}

// Power-of-two patterns
#test
{
    Swag.require(nzU64(0x00000001_00000000_u64) == 1)
    Swag.require(lzU64(0x00000001_00000000_u64) == 31)
    Swag.require(tzU64(0x00000001_00000000_u64) == 32)

    Swag.require(nzU16(0x0010_u16) == 1)
    Swag.require(lzU16(0x0010_u16) == 11)
    Swag.require(tzU16(0x0010_u16) == 4)
}

// Strict aliases
#test
{
    const nz = Swag.countOnes(cast(BitCountStrictU32, 0xF0F00000_u32))
    const tz = Swag.trailingZeros(cast(BitCountStrictU32, 0x00008000_u32))
    const lz = Swag.leadingZeros(cast(BitCountStrictU32, 0x00008000_u32))

    #assert(#typeof(nz) == BitCountStrictU32)
    #assert(#typeof(tz) == BitCountStrictU32)
    #assert(#typeof(lz) == BitCountStrictU32)

    Swag.require(nz == cast(BitCountStrictU32, 8))
    Swag.require(tz == cast(BitCountStrictU32, 15))
    Swag.require(lz == cast(BitCountStrictU32, 16))
}

#test
{
    let nz = nzStrictU32(cast(BitCountStrictU32, 0x55555555_u32))
    let tz = tzStrictU32(cast(BitCountStrictU32, 0x00010000_u32))
    let lz = lzStrictU32(cast(BitCountStrictU32, 0x00010000_u32))

    #assert(#typeof(nz) == BitCountStrictU32)
    #assert(#typeof(tz) == BitCountStrictU32)
    #assert(#typeof(lz) == BitCountStrictU32)

    Swag.require(nz == cast(BitCountStrictU32, 16))
    Swag.require(tz == cast(BitCountStrictU32, 16))
    Swag.require(lz == cast(BitCountStrictU32, 15))
}
