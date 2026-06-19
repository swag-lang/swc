#global fileprivate

interface I
{
    mtd foo() -> s32;
}

struct S {}

impl I for S
{
    mtd impl foo() -> s32 { return 1; }
}

struct W
{
    using s: S
}

func runDirectCast()->bool
{
    var s: S
    var i0 = cast(I) s
    return i0.foo() == 1
}

func runUsingCast()->bool
{
    var w: W
    var i1 = cast(I) w
    return i1.foo() == 1
}

#test
{
    const ok0 = #run runDirectCast()
    #assert(ok0)
}

#test
{
    const ok1 = #run runUsingCast()
    #assert(ok1)
}
