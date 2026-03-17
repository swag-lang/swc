#global fileprivate // 

#[Swag.NoInline]
func nzU8(value: u8)->u8 => @bitcountnz(value)

#[Swag.NoInline]
func nzU16(value: u16)->u16 => @bitcountnz(value)

#[Swag.NoInline]
func nzU32(value: u32)->u32 => @bitcountnz(value)

#[Swag.NoInline]
func nzU64(value: u64)->u64 => @bitcountnz(value)

#[Swag.NoInline]
func tzU8(value: u8)->u8 => @bitcounttz(value)

#[Swag.NoInline]
func tzU16(value: u16)->u16 => @bitcounttz(value)

#[Swag.NoInline]
func tzU32(value: u32)->u32 => @bitcounttz(value)

#[Swag.NoInline]
func tzU64(value: u64)->u64 => @bitcounttz(value)

#[Swag.NoInline]
func lzU8(value: u8)->u8 => @bitcountlz(value)

#[Swag.NoInline]
func lzU16(value: u16)->u16 => @bitcountlz(value)

#[Swag.NoInline]
func lzU32(value: u32)->u32 => @bitcountlz(value)

#[Swag.NoInline]
func lzU64(value: u64)->u64 => @bitcountlz(value)

#test
{
    @assert(nzU8(0b10110000'u8) == 3'u8)
    @assert(nzU16(0xF0F0'u16) == 8'u16)
    @assert(nzU32(0xFFFF0001'u32) == 17'u32)
    @assert(nzU64(0xF0000000_0000000F'u64) == 8'u64)
}

#test
{
    @assert(tzU8(0'u8) == 0'u8)
    @assert(tzU8(0x28'u8) == 4'u8)
    @assert(tzU16(0x8000'u16) == 16'u16)
    @assert(tzU32(1'u32) == 1'u32)
    @assert(tzU64(0x00010000_00000000'u64) == 49'u64)
}

#test
{
    @assert(lzU8(0'u8) == 0'u8)
    @assert(lzU8(1'u8) == 8'u8)
    @assert(lzU16(1'u16) == 16'u16)
    @assert(lzU32(0x80000000'u32) == 1'u32)
    @assert(lzU64(1'u64) == 64'u64)
}
