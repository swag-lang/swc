#global #[Swag.ExplicitNullability]
// 

#global private

func anyToS64(v: #nonull any)->s64
{
    return cast(s64) v
}

func sumAny(a: #nonull any, b: #nonull any)->s64
{
    return cast(s64) a + cast(s64) b
}

#test
{
    const c: #nonull any = 1's64
    let d = cast(s64) c
    @assert(d == 1)
}

#test
{
    const c: #nonull any = -123's32
    let d = cast(s32) c
    let e = cast(s64) c
    @assert(d == -123)
    @assert(e == -123)
}

#test
{
    const c: #nonull any = 987654321's64
    let d: s64 = cast() c
    @assert(d == 987654321)
}

#test
{
    const c: #nonull any = true
    let d = cast(bool) c
    @assert(d)
}

#test
{
    const c: #nonull any = 2.5'f64
    let d = cast(f64) c
    @assert(d == 2.5'f64)
}

#test
{
    const c: #nonull any = "run-any"
    let d = cast(#nonull string) c
    @assert(d == "run-any")
}

#test
{
    const c: #nonull any = 333's64
    let d = anyToS64(c)
    @assert(d == 333)
}

#test
{
    var a: s64 = 100
    var b: s64 = 23
    let d = sumAny(a, b)
    @assert(d == 123)
}

func s64Test(s: s64)
{
    @assert(s == 1)
}

enum A { B = 1 }
#test
{
    const c: #nonull any = A.B
    let d = cast(s64) c
    @assert(d == 1)
    s64Test(cast(s64) c)
}

#test
{
    var a: #nonull any = 1.0
    @assert(@kindof(a) == f32)
    var b = cast(f32) a
    @assert(b == 1.0'f32)
}

#test
{
    var a: #nonull any = 1
    @assert(@kindof(a) == s32)
    var b = cast(s32) a
    @assert(b == 1)
    //@print(b)
}
