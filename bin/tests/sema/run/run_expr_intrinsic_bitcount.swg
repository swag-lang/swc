#global fileprivate

#test
{
    #[Swag.NoInline]
    func nzU8(v: u8)->u8 => @bitcountnz(v)
    #[Swag.NoInline]
    func nzU16(v: u16)->u16 => @bitcountnz(v)
    #[Swag.NoInline]
    func nzU32(v: u32)->u32 => @bitcountnz(v)
    #[Swag.NoInline]
    func nzU64(v: u64)->u64 => @bitcountnz(v)

    #[Swag.NoInline]
    func tzU8(v: u8)->u8 => @bitcounttz(v)
    #[Swag.NoInline]
    func tzU16(v: u16)->u16 => @bitcounttz(v)
    #[Swag.NoInline]
    func tzU32(v: u32)->u32 => @bitcounttz(v)
    #[Swag.NoInline]
    func tzU64(v: u64)->u64 => @bitcounttz(v)

    #[Swag.NoInline]
    func lzU8(v: u8)->u8 => @bitcountlz(v)
    #[Swag.NoInline]
    func lzU16(v: u16)->u16 => @bitcountlz(v)
    #[Swag.NoInline]
    func lzU32(v: u32)->u32 => @bitcountlz(v)
    #[Swag.NoInline]
    func lzU64(v: u64)->u64 => @bitcountlz(v)

    const A0 = #run nzU8(0b10110000'u8)
    const A1 = #run nzU16(0xF0F0'u16)
    const A2 = #run nzU32(0xFFFF0001'u32)
    const A3 = #run nzU64(0xF0000000_0000000F'u64)

    const B0 = #run tzU8(0'u8)
    const B1 = #run tzU8(0x28'u8)
    const B2 = #run tzU16(0x8000'u16)
    const B3 = #run tzU32(1'u32)
    const B4 = #run tzU64(0x00010000_00000000'u64)

    const C0 = #run lzU8(0'u8)
    const C1 = #run lzU8(1'u8)
    const C2 = #run lzU16(1'u16)
    const C3 = #run lzU32(0x80000000'u32)
    const C4 = #run lzU64(1'u64)

    #assert(A0 == 3)
    #assert(A1 == 8)
    #assert(A2 == 17)
    #assert(A3 == 8)

    #assert(B0 == 0)
    #assert(B1 == 4)
    #assert(B2 == 16)
    #assert(B3 == 1)
    #assert(B4 == 49)

    #assert(C0 == 0)
    #assert(C1 == 8)
    #assert(C2 == 16)
    #assert(C3 == 1)
    #assert(C4 == 64)
}
