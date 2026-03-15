#global fileprivate // swc-option suite-test

enum SignedCode: s32
{
    Neg = -5,
    Pos = 9,
}

enum UnsignedCode: u16
{
    A = 7,
    B = 255,
}

#[Swag.EnumFlags]
enum Flags16: u16
{
    Read = 1,
    Write = 2,
    Exec = 4,
    High = 0x8000,
}

#assert(cast(s32) SignedCode.Neg == -5)
#assert(cast(s64) SignedCode.Pos == 9)
#assert(cast(f32) SignedCode.Pos == 9)

#assert(cast(u8) UnsignedCode.B == 255)
#assert(cast(u32) UnsignedCode.A == 7)
#assert(cast(f64) UnsignedCode.B == 255)

const FLAGS_ALL = Flags16.Read | Flags16.Write | Flags16.Exec
#assert(cast(u16) FLAGS_ALL == 7)
#assert(cast(u32) FLAGS_ALL == 7)
#assert(cast(s32) FLAGS_ALL == 7)
#assert(cast(bool) FLAGS_ALL == true)
#assert(cast(bool) (Flags16.Read & Flags16.Exec) == false)

#test
{
    let value = SignedCode.Neg
    @assert(cast(s32) value == -5)
    @assert(cast(f64) value == -5)
}

#test
{
    let value = UnsignedCode.B
    @assert(cast(u16) value == 255)
    @assert(cast(f32) value == 255)
}

#test
{
    let v = Flags16.Read | Flags16.Write
    @assert(cast(u16) v == 3)
    @assert(cast(bool) v)
}




