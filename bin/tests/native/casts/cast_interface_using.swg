#global fileprivate // swc-option suite-test

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
    discard i0.foo()
}

#test
{
    var w: W
    var i1 = cast(I) w
    discard i1.foo()
}

#test
{
    var b: Bad
    var i2 = cast(I) b // swc-expected-error {{sema_err_cannot_cast_to_interface}}
}
