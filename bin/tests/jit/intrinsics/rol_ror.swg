#global fileprivate // swc-option suite-jit

#test
{
    #[Swag.NoInline]
    func rolU8(v, n: u8)->u8 => @rol(v, n)
    #[Swag.NoInline]
    func rorU8(v, n: u8)->u8 => @ror(v, n)

    #[Swag.NoInline]
    func rolU16(v: u16, n: u8)->u16 => @rol(v, n)
    #[Swag.NoInline]
    func rorU16(v: u16, n: u8)->u16 => @ror(v, n)

    #[Swag.NoInline]
    func rolU32(v: u32, n: u8)->u32 => @rol(v, n)
    #[Swag.NoInline]
    func rorU32(v: u32, n: u8)->u32 => @ror(v, n)

    #[Swag.NoInline]
    func rolU64(v: u64, n: u8)->u64 => @rol(v, n)
    #[Swag.NoInline]
    func rorU64(v: u64, n: u8)->u64 => @ror(v, n)

    const A0 = #run rolU8(1'u8, 2)
    const A1 = #run rorU8(1'u8, 2)

    const B0 = #run rolU16(0x8000'u16, 2)
    const B1 = #run rorU16(1'u16, 2)

    const C0 = #run rolU32(0x80000000'u32, 2)
    const C1 = #run rorU32(1'u32, 2)

    const D0 = #run rolU64(0x80000000_00000000'u64, 2)
    const D1 = #run rorU64(1'u64, 2)

    #assert(A0 == 4)
    #assert(A1 == 64)
    #assert(B0 == 2)
    #assert(B1 == 0x4000)
    #assert(C0 == 2)
    #assert(C1 == 0x40000000)
    #assert(D0 == 2)
    #assert(D1 == 0x40000000_00000000)
}
