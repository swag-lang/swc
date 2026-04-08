#global fileprivate //

// ============================================================
// @bitcountnz — population count (number of set bits)
// ============================================================

#[Swag.NoInline]
func nzU8(value: u8)->u8 => @bitcountnz(value)

#[Swag.NoInline]
func nzU16(value: u16)->u16 => @bitcountnz(value)

#[Swag.NoInline]
func nzU32(value: u32)->u32 => @bitcountnz(value)

#[Swag.NoInline]
func nzU64(value: u64)->u64 => @bitcountnz(value)

// Compile-time — nz
#test
{
    const a: u8 = @bitcountnz(0'u8)
    const b: u8 = @bitcountnz(0xFF'u8)
    const c: u8 = @bitcountnz(0b10110000'u8)
    #assert(a == 0'u8)
    #assert(b == 8'u8)
    #assert(c == 3'u8)

    const d: u16 = @bitcountnz(0'u16)
    const e: u16 = @bitcountnz(0xFFFF'u16)
    const f: u16 = @bitcountnz(0xF0F0'u16)
    #assert(d == 0'u16)
    #assert(e == 16'u16)
    #assert(f == 8'u16)

    const g: u32 = @bitcountnz(0'u32)
    const h: u32 = @bitcountnz(0xFFFFFFFF'u32)
    const i: u32 = @bitcountnz(0x55555555'u32)
    #assert(g == 0'u32)
    #assert(h == 32'u32)
    #assert(i == 16'u32)

    const j: u64 = @bitcountnz(0'u64)
    const k: u64 = @bitcountnz(0xFFFFFFFF_FFFFFFFF'u64)
    const l: u64 = @bitcountnz(0xF0000000_0000000F'u64)
    #assert(j == 0'u64)
    #assert(k == 64'u64)
    #assert(l == 8'u64)
}

// u8
#test
{
    @assert(nzU8(0'u8) == 0)
    @assert(nzU8(0xFF'u8) == 8)
    @assert(nzU8(0b10110000'u8) == 3)
    @assert(nzU8(0b01010101'u8) == 4)
    @assert(nzU8(0b10101010'u8) == 4)
    @assert(nzU8(1'u8) == 1)
    @assert(nzU8(0x80'u8) == 1)
}

// u16
#test
{
    @assert(nzU16(0'u16) == 0)
    @assert(nzU16(0xFFFF'u16) == 16)
    @assert(nzU16(0xF0F0'u16) == 8)
    @assert(nzU16(0x0001'u16) == 1)
    @assert(nzU16(0x8000'u16) == 1)
    @assert(nzU16(0x5555'u16) == 8)
}

// u32
#test
{
    @assert(nzU32(0'u32) == 0)
    @assert(nzU32(0xFFFFFFFF'u32) == 32)
    @assert(nzU32(0xFFFF0001'u32) == 17)
    @assert(nzU32(0x80000000'u32) == 1)
    @assert(nzU32(1'u32) == 1)
    @assert(nzU32(0x55555555'u32) == 16)
    @assert(nzU32(0xAAAAAAAA'u32) == 16)
}

// u64
#test
{
    @assert(nzU64(0'u64) == 0)
    @assert(nzU64(0xFFFFFFFF_FFFFFFFF'u64) == 64)
    @assert(nzU64(0xF0000000_0000000F'u64) == 8)
    @assert(nzU64(1'u64) == 1)
    @assert(nzU64(0x80000000_00000000'u64) == 1)
    @assert(nzU64(0x55555555_55555555'u64) == 32)
}

// ============================================================
// @bitcounttz — count trailing zeros
// ============================================================

#[Swag.NoInline]
func tzU8(value: u8)->u8 => @bitcounttz(value)

#[Swag.NoInline]
func tzU16(value: u16)->u16 => @bitcounttz(value)

#[Swag.NoInline]
func tzU32(value: u32)->u32 => @bitcounttz(value)

#[Swag.NoInline]
func tzU64(value: u64)->u64 => @bitcounttz(value)

// Compile-time — tz
#test
{
    const a: u8 = @bitcounttz(0'u8)
    const b: u8 = @bitcounttz(1'u8)
    const c: u8 = @bitcounttz(0x80'u8)
    #assert(a == 8'u8)
    #assert(b == 0'u8)
    #assert(c == 7'u8)

    const d: u16 = @bitcounttz(0'u16)
    const e: u16 = @bitcounttz(0x8000'u16)
    #assert(d == 16'u16)
    #assert(e == 15'u16)

    const f: u32 = @bitcounttz(0'u32)
    const g: u32 = @bitcounttz(0x80000000'u32)
    #assert(f == 32'u32)
    #assert(g == 31'u32)

    const h: u64 = @bitcounttz(0'u64)
    const i: u64 = @bitcounttz(0x80000000_00000000'u64)
    #assert(h == 64'u64)
    #assert(i == 63'u64)
}

// u8
#test
{
    @assert(tzU8(0'u8) == 8)
    @assert(tzU8(1'u8) == 0)
    @assert(tzU8(0x80'u8) == 7)
    @assert(tzU8(0x28'u8) == 3)
    @assert(tzU8(0xFF'u8) == 0)
    @assert(tzU8(0b00010000'u8) == 4)
}

// u16
#test
{
    @assert(tzU16(0'u16) == 16)
    @assert(tzU16(1'u16) == 0)
    @assert(tzU16(0x8000'u16) == 15)
    @assert(tzU16(0xFFFF'u16) == 0)
    @assert(tzU16(0x0100'u16) == 8)
}

// u32
#test
{
    @assert(tzU32(0'u32) == 32)
    @assert(tzU32(1'u32) == 0)
    @assert(tzU32(0x80000000'u32) == 31)
    @assert(tzU32(0xFFFFFFFF'u32) == 0)
    @assert(tzU32(0x00010000'u32) == 16)
}

// u64
#test
{
    @assert(tzU64(0'u64) == 64)
    @assert(tzU64(1'u64) == 0)
    @assert(tzU64(0x80000000_00000000'u64) == 63)
    @assert(tzU64(0xFFFFFFFF_FFFFFFFF'u64) == 0)
    @assert(tzU64(0x00010000_00000000'u64) == 48)
}

// ============================================================
// @bitcountlz — count leading zeros
// ============================================================

#[Swag.NoInline]
func lzU8(value: u8)->u8 => @bitcountlz(value)

#[Swag.NoInline]
func lzU16(value: u16)->u16 => @bitcountlz(value)

#[Swag.NoInline]
func lzU32(value: u32)->u32 => @bitcountlz(value)

#[Swag.NoInline]
func lzU64(value: u64)->u64 => @bitcountlz(value)

// Compile-time — lz
#test
{
    const a: u8 = @bitcountlz(0'u8)
    const b: u8 = @bitcountlz(1'u8)
    const c: u8 = @bitcountlz(0x80'u8)
    #assert(a == 8'u8)
    #assert(b == 7'u8)
    #assert(c == 0'u8)

    const d: u16 = @bitcountlz(0'u16)
    const e: u16 = @bitcountlz(1'u16)
    const f: u16 = @bitcountlz(0x8000'u16)
    #assert(d == 16'u16)
    #assert(e == 15'u16)
    #assert(f == 0'u16)

    const g: u32 = @bitcountlz(0'u32)
    const h: u32 = @bitcountlz(1'u32)
    const i: u32 = @bitcountlz(0x80000000'u32)
    #assert(g == 32'u32)
    #assert(h == 31'u32)
    #assert(i == 0'u32)

    const j: u64 = @bitcountlz(0'u64)
    const k: u64 = @bitcountlz(1'u64)
    const l: u64 = @bitcountlz(0x80000000_00000000'u64)
    #assert(j == 64'u64)
    #assert(k == 63'u64)
    #assert(l == 0'u64)
}

// u8
#test
{
    @assert(lzU8(0'u8) == 8)
    @assert(lzU8(1'u8) == 7)
    @assert(lzU8(0x80'u8) == 0)
    @assert(lzU8(0xFF'u8) == 0)
    @assert(lzU8(0x0F'u8) == 4)
    @assert(lzU8(0x40'u8) == 1)
}

// u16
#test
{
    @assert(lzU16(0'u16) == 16)
    @assert(lzU16(1'u16) == 15)
    @assert(lzU16(0x8000'u16) == 0)
    @assert(lzU16(0xFFFF'u16) == 0)
    @assert(lzU16(0x00FF'u16) == 8)
}

// u32
#test
{
    @assert(lzU32(0'u32) == 32)
    @assert(lzU32(1'u32) == 31)
    @assert(lzU32(0x80000000'u32) == 0)
    @assert(lzU32(0xFFFFFFFF'u32) == 0)
    @assert(lzU32(0x0000FFFF'u32) == 16)
}

// u64
#test
{
    @assert(lzU64(0'u64) == 64)
    @assert(lzU64(1'u64) == 63)
    @assert(lzU64(0x80000000_00000000'u64) == 0)
    @assert(lzU64(0xFFFFFFFF_FFFFFFFF'u64) == 0)
    @assert(lzU64(0x00000000_FFFFFFFF'u64) == 32)
}

// ============================================================
// Cross-intrinsic consistency: single-bit patterns
// ============================================================

#test
{
    @assert(nzU8(0x01'u8) == 1)
    @assert(lzU8(0x01'u8) == 7)
    @assert(tzU8(0x01'u8) == 0)

    @assert(nzU8(0x80'u8) == 1)
    @assert(lzU8(0x80'u8) == 0)
    @assert(tzU8(0x80'u8) == 7)

    @assert(nzU32(0x00008000'u32) == 1)
    @assert(lzU32(0x00008000'u32) == 16)
    @assert(tzU32(0x00008000'u32) == 15)
}

// Power-of-two patterns
#test
{
    @assert(nzU64(0x00000001_00000000'u64) == 1)
    @assert(lzU64(0x00000001_00000000'u64) == 31)
    @assert(tzU64(0x00000001_00000000'u64) == 32)

    @assert(nzU16(0x0010'u16) == 1)
    @assert(lzU16(0x0010'u16) == 11)
    @assert(tzU16(0x0010'u16) == 4)
}
