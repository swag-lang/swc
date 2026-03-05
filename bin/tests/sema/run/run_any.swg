#global fileprivate

func anyToS64(v: any)->s64
{
    return cast(s64) v
}

func sumAny(a: any, b: any)->s64
{
    return cast(s64) a + cast(s64) b
}

#run
{
    const c: any = 1
    let d = cast(s64) c
    @assert(d == 1)
}

#run
{
    const c: any = -123's32
    let d = cast(s32) c
    let e = cast(s64) c
    @assert(d == -123)
    @assert(e == -123)
}

#run
{
    const c: any = 987654321's64
    let d: s64 = cast() c
    @assert(d == 987654321)
}

#run
{
    const c: any = true
    let d = cast(bool) c
    @assert(d)
}

#run
{
    const c: any = 2.5'f64
    let d = cast(f64) c
    @assert(d == 2.5'f64)
}

#run
{
    const c: any = "run-any"
    let d = cast(string) c
    @assert(d == "run-any")
}

#run
{
    const c: any = 333's64
    let d = anyToS64(c)
    @assert(d == 333)
}

#run
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
#run
{
    const c: any = A.B
    let d = cast(s64) c
    @assert(d == 1)
    //s64Test(c)
}
