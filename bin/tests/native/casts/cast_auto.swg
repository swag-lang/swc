#global fileprivate // swc-option suite-test

const A: s32 = 1
const B: bool = cast() A
#assert(B == true)

func toto(ptr: *u32) {}
func takes_s32(v: s32) {}
func takes_u64(v: u64) {}
func takes_f64(v: f64) {}
#test
{
    var ptr: *u64
    toto(cast() ptr)
}

#test
{
    var f: f32 = 12.75
    takes_s32(cast() f)
}


#test
{
    const B: bool = true
    const S: s32 = cast() B
    #assert(S == 1)
}

#test
{
    func ret_u64() -> u64 { return 42 }
    var y: s32 = cast() ret_u64()
}

#test
{
    #[Swag.Inline]
    func ret_u64() -> u64 { return 42 }
    var y: s32 = cast() ret_u64()
}







#test
{
    var v: u16 = 7
    takes_u64(cast() v)
    takes_f64(cast() v)
}




#test
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

#test
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: const &A = &x
    var p: const *A = &r
}

#test
{
    struct A
    {
        v: s32
    }

    var x: A
    var r: const &A = &x
}

#[Swag.Inline]
func ret_u64_short() => cast(u64) 42
func a_takes_s32(v: s32) {}


#test
{
    var y: s32 = cast() ret_u64_short()
    @assert(y == 42)
}


#test
{
    a_takes_s32(cast() ret_u64_short())
}
