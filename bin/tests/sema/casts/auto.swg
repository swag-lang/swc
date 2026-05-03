#global fileprivate

const A: s32 = 1
const B: bool = cast() A
#assert(B == true)

func toto(ptr: *u32) {}
func takes_s32(v: s32) {}
func takes_u64(v: u64) {}
func takes_f64(v: f64) {}

func semaTest001()
{
    var u: u32 = 100
    var s: s32 = cast() u
    var b: bool = cast() u
}

func semaTest002()
{
    const B: bool = true
    const S: s32 = cast() B
    #assert(S == 1)
}

func semaTest003()
{
    var a: u8 = 255
    var b: u16 = cast() a
    var c: u32 = cast() a
}

func semaTest004()
{
    var x: s32 = -10
    var y: f32 = cast() x
}

func semaTest005()
{
    var f: f64 = 3.14159
    var g: f32 = cast() f
}

func semaTest006()
{
    var arr: [10]s32
    var ptr: *s32 = cast() &arr[0]
}

func semaTest007()
{
    var p: *u32 = null
}

func semaTest008()
{
    var p64: *u64
    var p32: *u32 = cast() p64
}

func semaTest009()
{
    var v: u16 = 7
    takes_u64(cast() v)
    takes_f64(cast() v)
}

func semaTest010()
{
    var b0: bool = cast() 0
    var b1: bool = cast() 1
}

func semaTest011()
{
    var f: f32 = 42.75
    var i: s32 = cast() f
}

func semaTest012()
{
    var p: *u32 = cast() null
    var s: string = cast() null
    var sl: [..] s32 = cast() null
}

func semaTest013()
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: &A = &x
    var p: *A = &r
    #assert(#typeof(p) == *A)
}

func semaTest014()
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: const &A = &x
    var p: const *A = &r
}

#[Swag.Inline]
func ret_u64_short() => cast(u64) 42
func a_takes_s32(v: s32) {}

func semaTest015()
{
    var y: s32 = cast() ret_u64_short()
    @assert(y == 42)
}

func semaTest016()
{
    a_takes_s32(cast() ret_u64_short())
}
