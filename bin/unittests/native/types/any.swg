// 

#global private

func anyToS64(v: any)->s64
{
    return cast #assume(s64) v
}

func sumAny(a: any, b: any)->s64
{
    return cast #assume(s64) a + cast #assume(s64) b
}

#test
{
    const c: any = 1's64
    let d = cast #assume(s64) c
    Swag.assert(d == 1)
}

#test
{
    const c: any = -123's32
    let d = cast #assume(s32) c
    let e = cast(s64) d
    Swag.assert(d == -123)
    Swag.assert(e == -123)
}

#test
{
    const c: any = 987654321's64
    let d: s64 = cast #assume() c
    Swag.assert(d == 987654321)
}

#test
{
    const c: any = true
    let d = cast #assume(bool) c
    Swag.assert(d)
}

#test
{
    const c: any = 2.5'f64
    let d = cast #assume(f64) c
    Swag.assert(d == 2.5'f64)
}

#test
{
    const c: any = "run-any"
    let d = cast #assume(string) c
    Swag.assert(d == "run-any")
}

#test
{
    const c: any = 333's64
    let d = anyToS64(c)
    Swag.assert(d == 333)
}

#test
{
    var a: s64 = 100
    var b: s64 = 23
    let d      = sumAny(a, b)
    Swag.assert(d == 123)
}

func s64Test(s: s64)
{
    Swag.assert(s == 1)
}

enum A { B = 1 }
#test
{
    const c: any = A.B
    let d = cast(s64) cast #assume(A) c
    Swag.assert(d == 1)
    s64Test(cast(s64) cast #assume(A) c)
}

#test
{
    var a: any = 1.0
    Swag.assert(Swag.kindOf(a) == f32)
    var b = cast #assume(f32) a
    Swag.assert(b == 1.0'f32)
}

#test
{
    var a: any = 1
    Swag.assert(Swag.kindOf(a) == s32)
    var b = cast #assume(s32) a
    Swag.assert(b == 1)
    // Swag.print(b)
}
