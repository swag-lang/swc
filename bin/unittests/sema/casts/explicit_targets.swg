#global private

const A: s32  = 1
const B: bool = cast(bool, A)
#assert(B == true)

func toto(_: *u32) {}
func takes_s32(_: s32) {}
func takes_u64(_: u64) {}
func takes_f64(_: f64) {}

func semaTest001()
{
    var u: u32 = 100
    var s: s32 = cast(s32, u)
    discard s
    var b: bool = cast(bool, u)
    discard b
}

func semaTest002()
{
    const B: bool = true
    const S: s32  = cast(s32, B)
    #assert(S == 1)
}

func semaTest003()
{
    var a: u8  = 255
    var b: u16 = cast(u16, a)
    discard b
    var c: u32 = cast(u32, a)
    discard c
}

func semaTest004()
{
    var x: s32 = -10
    var y: f32 = cast(f32, x)
    discard y
}

func semaTest005()
{
    var f: f64 = 3.14159
    var g: f32 = cast(f32, f)
    discard g
}

func semaTest006()
{
    var arr: [10]s32
    var ptr: *s32 = cast(*s32, &arr[0])
    discard ptr
}

func semaTest007()
{
    var p: *u32? = null
    discard p
}

func semaTest008()
{
    var x64: u64
    var p64: *u64 = &x64
    var p32: *u32 = cast(*u32, p64)
    discard p32
}

func semaTest009()
{
    var v: u16 = 7
    takes_u64(cast(u64, v))
    takes_f64(cast(f64, v))
}

func semaTest010()
{
    var b0: bool = cast(bool, 0)
    discard b0
    var b1: bool = cast(bool, 1)
    discard b1
}

func semaTest011()
{
    var f: f32 = 42.75
    var i: s32 = cast(s32, f)
    discard i
}

func semaTest012()
{
    var p: *u32? = cast(*u32?, null)
    discard p
    var s: string? = cast(string?, null)
    discard s
    var sl: [..] s32? = cast([..] s32?, null)
    discard sl
}

func semaTest013()
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: *A = &x
    var p: *A = r
    #assert(#typeof(p) == *A)
}

func semaTest014()
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: const *A = &x
    var p: const *A = r
    discard p
}

#[Swag.Inline]
func ret_u64_short() => cast(u64, 42)
func a_takes_s32(_: s32) {}

func semaTest015()
{
    var y: s32 = cast(s32, ret_u64_short())
    Swag.assert(y == 42)
}

func semaTest016()
{
    a_takes_s32(cast(s32, ret_u64_short()))
}
