#global internal

func takes_f32(v: f32) {}
func takes_f64(v: f64) {}

#test
{
    var a: u8 = 10
    var b: f32 = a
    var c: f64 = a
}

#test
{
    var a: u64 = 10
    var b: f64 = a
    var c: f32 = a // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    const A: u64 = 10
    const B: f32 = A // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: s32 = -10
    takes_f32(a)
    takes_f64(a)
}

#test
{
    var a: s64 = -10
    takes_f64(a)
    takes_f32(a) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: u16 = 10
    var b: f32 = a
    var c: f64 = a
}

#test
{
    var a: u32 = 10
    takes_f32(a)
    takes_f64(a)
}

#test
{
    var a: s16 = -10
    var b: f32 = a
    var c: f64 = a
}

#test
{
    var a: f32 = 12.5
    var b: f64 = a
}

#test
{
    var a: f64 = 12.5
    var b: f32 = a // swc-expected-error {{sema_err_cannot_cast}}
}
