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

struct T {}

struct Bad
{
    using t: T
}

#test
{
    var s: S
    var i0 = cast(I) s
    @assert(i0.foo() == 1)
}

#test
{
    var w: W
    var i1 = cast(I) w
    @assert(i1.foo() == 1)
}
