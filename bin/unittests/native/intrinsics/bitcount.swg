#global private     //

#[Swag.Strict]
alias BitCountStrictU32 = u32

// ============================================================
// Swag.bitCountNz — population count (number of set bits)
// ============================================================

#[Swag.NoInline]
func nzU8(value: u8)->u8 => Swag.bitCountNz(value)

#[Swag.NoInline]
func nzU16(value: u16)->u16 => Swag.bitCountNz(value)

#[Swag.NoInline]
func nzU32(value: u32)->u32 => Swag.bitCountNz(value)

#[Swag.NoInline]
func nzU64(value: u64)->u64 => Swag.bitCountNz(value)

#[Swag.NoInline]
func nzStrictU32(value: BitCountStrictU32)->BitCountStrictU32 => Swag.bitCountNz(value)

// Compile-time — nz
#test
{
    const a: u8 = Swag.bitCountNz(0'u8)
    const b: u8 = Swag.bitCountNz(0xFF'u8)
    const c: u8 = Swag.bitCountNz(0b10110000'u8)
    #assert(a == 0'u8)
    #assert(b == 8'u8)
    #assert(c == 3'u8)

    const d: u16 = Swag.bitCountNz(0'u16)
    const e: u16 = Swag.bitCountNz(0xFFFF'u16)
    const f: u16 = Swag.bitCountNz(0xF0F0'u16)
    #assert(d == 0'u16)
    #assert(e == 16'u16)
    #assert(f == 8'u16)

    const g: u32 = Swag.bitCountNz(0'u32)
    const h: u32 = Swag.bitCountNz(0xFFFFFFFF'u32)
    const i: u32 = Swag.bitCountNz(0x55555555'u32)
    #assert(g == 0'u32)
    #assert(h == 32'u32)
    #assert(i == 16'u32)

    const j: u64 = Swag.bitCountNz(0'u64)
    const k: u64 = Swag.bitCountNz(0xFFFFFFFF_FFFFFFFF'u64)
    const l: u64 = Swag.bitCountNz(0xF0000000_0000000F'u64)
    #assert(j == 0'u64)
    #assert(k == 64'u64)
    #assert(l == 8'u64)
}

// u8
#test
{
    Swag.assert(nzU8(0'u8) == 0)
    Swag.assert(nzU8(0xFF'u8) == 8)
    Swag.assert(nzU8(0b10110000'u8) == 3)
    Swag.assert(nzU8(0b01010101'u8) == 4)
    Swag.assert(nzU8(0b10101010'u8) == 4)
    Swag.assert(nzU8(1'u8) == 1)
    Swag.assert(nzU8(0x80'u8) == 1)
}

// u16
#test
{
    Swag.assert(nzU16(0'u16) == 0)
    Swag.assert(nzU16(0xFFFF'u16) == 16)
    Swag.assert(nzU16(0xF0F0'u16) == 8)
    Swag.assert(nzU16(0x0001'u16) == 1)
    Swag.assert(nzU16(0x8000'u16) == 1)
    Swag.assert(nzU16(0x5555'u16) == 8)
}

// u32
#test
{
    Swag.assert(nzU32(0'u32) == 0)
    Swag.assert(nzU32(0xFFFFFFFF'u32) == 32)
    Swag.assert(nzU32(0xFFFF0001'u32) == 17)
    Swag.assert(nzU32(0x80000000'u32) == 1)
    Swag.assert(nzU32(1'u32) == 1)
    Swag.assert(nzU32(0x55555555'u32) == 16)
    Swag.assert(nzU32(0xAAAAAAAA'u32) == 16)
}

// u64
#test
{
    Swag.assert(nzU64(0'u64) == 0)
    Swag.assert(nzU64(0xFFFFFFFF_FFFFFFFF'u64) == 64)
    Swag.assert(nzU64(0xF0000000_0000000F'u64) == 8)
    Swag.assert(nzU64(1'u64) == 1)
    Swag.assert(nzU64(0x80000000_00000000'u64) == 1)
    Swag.assert(nzU64(0x55555555_55555555'u64) == 32)
}

// ============================================================
// Swag.bitCountTz — count trailing zeros
// ============================================================

#[Swag.NoInline]
func tzU8(value: u8)->u8 => Swag.bitCountTz(value)

#[Swag.NoInline]
func tzU16(value: u16)->u16 => Swag.bitCountTz(value)

#[Swag.NoInline]
func tzU32(value: u32)->u32 => Swag.bitCountTz(value)

#[Swag.NoInline]
func tzU64(value: u64)->u64 => Swag.bitCountTz(value)

#[Swag.NoInline]
func tzStrictU32(value: BitCountStrictU32)->BitCountStrictU32 => Swag.bitCountTz(value)

// Compile-time — tz
#test
{
    const a: u8 = Swag.bitCountTz(0'u8)
    const b: u8 = Swag.bitCountTz(1'u8)
    const c: u8 = Swag.bitCountTz(0x80'u8)
    #assert(a == 8'u8)
    #assert(b == 0'u8)
    #assert(c == 7'u8)

    const d: u16 = Swag.bitCountTz(0'u16)
    const e: u16 = Swag.bitCountTz(0x8000'u16)
    #assert(d == 16'u16)
    #assert(e == 15'u16)

    const f: u32 = Swag.bitCountTz(0'u32)
    const g: u32 = Swag.bitCountTz(0x80000000'u32)
    #assert(f == 32'u32)
    #assert(g == 31'u32)

    const h: u64 = Swag.bitCountTz(0'u64)
    const i: u64 = Swag.bitCountTz(0x80000000_00000000'u64)
    #assert(h == 64'u64)
    #assert(i == 63'u64)
}

// u8
#test
{
    Swag.assert(tzU8(0'u8) == 8)
    Swag.assert(tzU8(1'u8) == 0)
    Swag.assert(tzU8(0x80'u8) == 7)
    Swag.assert(tzU8(0x28'u8) == 3)
    Swag.assert(tzU8(0xFF'u8) == 0)
    Swag.assert(tzU8(0b00010000'u8) == 4)
}

// u16
#test
{
    Swag.assert(tzU16(0'u16) == 16)
    Swag.assert(tzU16(1'u16) == 0)
    Swag.assert(tzU16(0x8000'u16) == 15)
    Swag.assert(tzU16(0xFFFF'u16) == 0)
    Swag.assert(tzU16(0x0100'u16) == 8)
}

// u32
#test
{
    Swag.assert(tzU32(0'u32) == 32)
    Swag.assert(tzU32(1'u32) == 0)
    Swag.assert(tzU32(0x80000000'u32) == 31)
    Swag.assert(tzU32(0xFFFFFFFF'u32) == 0)
    Swag.assert(tzU32(0x00010000'u32) == 16)
}

// u64
#test
{
    Swag.assert(tzU64(0'u64) == 64)
    Swag.assert(tzU64(1'u64) == 0)
    Swag.assert(tzU64(0x80000000_00000000'u64) == 63)
    Swag.assert(tzU64(0xFFFFFFFF_FFFFFFFF'u64) == 0)
    Swag.assert(tzU64(0x00010000_00000000'u64) == 48)
}

// ============================================================
// Swag.bitCountLz — count leading zeros
// ============================================================

#[Swag.NoInline]
func lzU8(value: u8)->u8 => Swag.bitCountLz(value)

#[Swag.NoInline]
func lzU16(value: u16)->u16 => Swag.bitCountLz(value)

#[Swag.NoInline]
func lzU32(value: u32)->u32 => Swag.bitCountLz(value)

#[Swag.NoInline]
func lzU64(value: u64)->u64 => Swag.bitCountLz(value)

#[Swag.NoInline]
func lzStrictU32(value: BitCountStrictU32)->BitCountStrictU32 => Swag.bitCountLz(value)

// Compile-time — lz
#test
{
    const a: u8 = Swag.bitCountLz(0'u8)
    const b: u8 = Swag.bitCountLz(1'u8)
    const c: u8 = Swag.bitCountLz(0x80'u8)
    #assert(a == 8'u8)
    #assert(b == 7'u8)
    #assert(c == 0'u8)

    const d: u16 = Swag.bitCountLz(0'u16)
    const e: u16 = Swag.bitCountLz(1'u16)
    const f: u16 = Swag.bitCountLz(0x8000'u16)
    #assert(d == 16'u16)
    #assert(e == 15'u16)
    #assert(f == 0'u16)

    const g: u32 = Swag.bitCountLz(0'u32)
    const h: u32 = Swag.bitCountLz(1'u32)
    const i: u32 = Swag.bitCountLz(0x80000000'u32)
    #assert(g == 32'u32)
    #assert(h == 31'u32)
    #assert(i == 0'u32)

    const j: u64 = Swag.bitCountLz(0'u64)
    const k: u64 = Swag.bitCountLz(1'u64)
    const l: u64 = Swag.bitCountLz(0x80000000_00000000'u64)
    #assert(j == 64'u64)
    #assert(k == 63'u64)
    #assert(l == 0'u64)
}

// u8
#test
{
    Swag.assert(lzU8(0'u8) == 8)
    Swag.assert(lzU8(1'u8) == 7)
    Swag.assert(lzU8(0x80'u8) == 0)
    Swag.assert(lzU8(0xFF'u8) == 0)
    Swag.assert(lzU8(0x0F'u8) == 4)
    Swag.assert(lzU8(0x40'u8) == 1)
}

// u16
#test
{
    Swag.assert(lzU16(0'u16) == 16)
    Swag.assert(lzU16(1'u16) == 15)
    Swag.assert(lzU16(0x8000'u16) == 0)
    Swag.assert(lzU16(0xFFFF'u16) == 0)
    Swag.assert(lzU16(0x00FF'u16) == 8)
}

// u32
#test
{
    Swag.assert(lzU32(0'u32) == 32)
    Swag.assert(lzU32(1'u32) == 31)
    Swag.assert(lzU32(0x80000000'u32) == 0)
    Swag.assert(lzU32(0xFFFFFFFF'u32) == 0)
    Swag.assert(lzU32(0x0000FFFF'u32) == 16)
}

// u64
#test
{
    Swag.assert(lzU64(0'u64) == 64)
    Swag.assert(lzU64(1'u64) == 63)
    Swag.assert(lzU64(0x80000000_00000000'u64) == 0)
    Swag.assert(lzU64(0xFFFFFFFF_FFFFFFFF'u64) == 0)
    Swag.assert(lzU64(0x00000000_FFFFFFFF'u64) == 32)
}

// ============================================================
// Cross-intrinsic consistency: single-bit patterns
// ============================================================

#test
{
    Swag.assert(nzU8(0x01'u8) == 1)
    Swag.assert(lzU8(0x01'u8) == 7)
    Swag.assert(tzU8(0x01'u8) == 0)

    Swag.assert(nzU8(0x80'u8) == 1)
    Swag.assert(lzU8(0x80'u8) == 0)
    Swag.assert(tzU8(0x80'u8) == 7)

    Swag.assert(nzU32(0x00008000'u32) == 1)
    Swag.assert(lzU32(0x00008000'u32) == 16)
    Swag.assert(tzU32(0x00008000'u32) == 15)
}

// Power-of-two patterns
#test
{
    Swag.assert(nzU64(0x00000001_00000000'u64) == 1)
    Swag.assert(lzU64(0x00000001_00000000'u64) == 31)
    Swag.assert(tzU64(0x00000001_00000000'u64) == 32)

    Swag.assert(nzU16(0x0010'u16) == 1)
    Swag.assert(lzU16(0x0010'u16) == 11)
    Swag.assert(tzU16(0x0010'u16) == 4)
}

// Strict aliases
#test
{
    const nz = Swag.bitCountNz(cast(BitCountStrictU32) 0xF0F00000'u32)
    const tz = Swag.bitCountTz(cast(BitCountStrictU32) 0x00008000'u32)
    const lz = Swag.bitCountLz(cast(BitCountStrictU32) 0x00008000'u32)

    #assert(#typeof(nz) == BitCountStrictU32)
    #assert(#typeof(tz) == BitCountStrictU32)
    #assert(#typeof(lz) == BitCountStrictU32)

    Swag.assert(nz == cast(BitCountStrictU32) 8)
    Swag.assert(tz == cast(BitCountStrictU32) 15)
    Swag.assert(lz == cast(BitCountStrictU32) 16)
}

#test
{
    let nz = nzStrictU32(cast(BitCountStrictU32) 0x55555555'u32)
    let tz = tzStrictU32(cast(BitCountStrictU32) 0x00010000'u32)
    let lz = lzStrictU32(cast(BitCountStrictU32) 0x00010000'u32)

    #assert(#typeof(nz) == BitCountStrictU32)
    #assert(#typeof(tz) == BitCountStrictU32)
    #assert(#typeof(lz) == BitCountStrictU32)

    Swag.assert(nz == cast(BitCountStrictU32) 16)
    Swag.assert(tz == cast(BitCountStrictU32) 16)
    Swag.assert(lz == cast(BitCountStrictU32) 15)
}
