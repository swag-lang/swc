#global internal

const a: s32 = 1
const b: bool = cast() a
const c: bool = a // swc-expected-error {{sema_err_cannot_cast}}
#assert(b == true)

func toto(ptr: *u32) {}
func takes_s32(v: s32) {}
#test
{
    var ptr: *u64
    toto(cast() ptr)
    toto(ptr) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var f: f32 = 12.75
    takes_s32(f) // swc-expected-error {{sema_err_cannot_cast}}
    takes_s32(cast() f)
}

#test
{
    var u: u32 = 100
    var s: s32 = cast() u
    var b: bool = cast() u
}

#test
{
    const b: bool = true
    const s: s32 = cast() b
    #assert(s == 1)
}

#test
{
    func ret_u64() -> u64 { return 42 }
    var x: s32 = ret_u64() // swc-expected-error {{sema_err_cannot_cast}}
    var y: s32 = cast() ret_u64()
}

#test
{
    var a: u8 = 255
    var b: u16 = cast() a
    var c: u32 = cast() a
}

#test
{
    var x: s32 = -10
    var y: f32 = cast() x
}

#test
{
    var f: f64 = 3.14159
    var g: f32 = cast() f
}

#test
{
    var arr: [10]s32
    var ptr: *s32 = cast() &arr[0]
}

#test
{
    var p: *u32 = null
}
