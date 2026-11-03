#global private

const A: s32  = 1
const B: bool = cast(A)
#assert(B == true)

var gAutoPtr: *u32?
var gAutoS32: s32
var gAutoU64: u64
var gAutoF64: f64
var gAutoX64: u64
func toto(ptr: *u32) { gAutoPtr = ptr }
func takes_s32(v: s32) { gAutoS32 = v }
func takes_u64(v: u64) { gAutoU64 = v }
func takes_f64(v: f64) { gAutoF64 = v }
#test
{
    var ptr: *u64 = &gAutoX64
    toto(cast(ptr))
    Swag.require(gAutoPtr == cast(*u32, ptr))
}

#test
{
    var f: f32 = 12.75
    takes_s32(cast(f))
    Swag.require(gAutoS32 == 12)
}

#test
{
    const B: bool = true
    const S: s32  = cast(B)
    #assert(S == 1)
    Swag.require(S == 1)
}

#test
{
    func ret_u64()->u64 { return 42 }
    var y: s32 = cast(ret_u64())
    Swag.require(y == 42)
}

#test
{
    #[Swag.Inline]
    func ret_u64()->u64 { return 42 }
    var y: s32 = cast(ret_u64())
    Swag.require(y == 42)
}

#test
{
    var v: u16 = 7
    takes_u64(cast(v))
    takes_f64(cast(v))
    Swag.require(gAutoU64 == 7)
    Swag.require(gAutoF64 == 7.0)
}

#test
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: *A = &x
    var p: *A = r
    #assert(#typeof(p) == *A)
    Swag.require(#typeof(p) == *A)
}

#test
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: const *A = &x
    var p: const *A = r
    Swag.require(#typeof(p) == const *A)
}

#test
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: const *A = &x
    Swag.require(#typeof(r) == const *A)
}

#[Swag.Inline]
func ret_u64_short() => cast(u64, 42)
func a_takes_s32(v: s32) { gAutoS32 = v }

#test
{
    var y: s32 = cast(ret_u64_short())
    Swag.require(y == 42)
}

#test
{
    a_takes_s32(cast(ret_u64_short()))
    Swag.require(gAutoS32 == 42)
}
