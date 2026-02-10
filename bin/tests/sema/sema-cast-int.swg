#global internal

func takes_u32(v: u32) {}
func takes_u8(v: u8) {}
func takes_s32(v: s32) {}

#test
{
    var a: u8 = 10
    var b: u16 = a
    var c: u32 = b
    var d: u64 = c
}

#test
{
    var a: s8 = -10
    var b: s16 = a
    var c: s32 = b
    var d: s64 = c
}

#test
{
    var a: u32 = 10
    var b: s32 = a
    var c: u32 = b
}

#test
{
    var a: u64 = 10
    var b: u32 = a // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: s64 = -10
    var b: s32 = a // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    const A: u64 = 255
    const B: u8 = A
    #assert(B == 255'u8)
}

#test
{
    const A: u64 = 256
    const B: u8 = A // swc-expected-error {{sema_err_literal_overflow}}
}

#test
{
    const A: s32 = -1
    const B: u8 = A // swc-expected-error {{sema_err_signed_unsigned}}
}

#test
{
    var a: u16 = 10
    takes_u32(a)
    takes_u8(a) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: u16 = 10
    var b: u32 = 0
    b = a
    var c: u8 = 0
    c = a // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: f32 = 10.5
    var b: s32 = a // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: f64 = 10.5
    takes_u32(a) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: f64 = 10.5
    takes_s32(a) // swc-expected-error {{sema_err_cannot_cast}}
}
