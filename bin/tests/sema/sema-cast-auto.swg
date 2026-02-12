#global internal

const A: s32 = 1
const B: bool = cast() A
const C: bool = A // swc-expected-error {{sema_err_cannot_cast}}
#assert(B == true)

func toto(ptr: *u32) {}
func takes_s32(v: s32) {}
func takes_u64(v: u64) {}
func takes_f64(v: f64) {}
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
    const B: bool = true
    const S: s32 = cast() B
    #assert(S == 1)
}
/*
#test
{
    func ret_u64() -> u64 { return 42 }
    var x: s32 = ret_u64() // swc-expected-error {{sema_err_cannot_cast}}
    var y: s32 = cast() ret_u64()
}
*/
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

#test
{
    var p64: *u64
    var p32: *u32 = cast() p64
}

#test
{
    var v: u16 = 7
    takes_u64(cast() v)
    takes_f64(cast() v)
}

#test
{
    var b0: bool = cast() 0
    var b1: bool = cast() 1
}

#test
{
    var f: f32 = 42.75
    var i: s32 = cast() f
}

#test
{
    var p: *u32 = cast() null
    var s: string = cast() null
    var sl: [..] s32 = cast() null
}
