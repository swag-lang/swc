#global fileprivate

// Test multiple interfaces implemented by the same struct,
// interface reassignment, and interface as return value.

interface IFoo
{
    mtd foo()->s32;
}

interface IBar
{
    mtd bar()->s32;
}

struct Multi
{
    x: s32 = 5
    y: s32 = 7
}

impl IFoo for Multi
{
    mtd impl foo()->s32 => .x
}

impl IBar for Multi
{
    mtd impl bar()->s32 => .y
}

// Interface as function return value.
func makeFoo()->IFoo
{
    var m: Multi
    return cast(IFoo) m
}

func makeBar()->IBar
{
    var m: Multi
    return cast(IBar) m
}

// Multiple interfaces on the same struct.
#test
{
    var m: Multi
    var f = cast(IFoo) m
    var b = cast(IBar) m
    @assert(f.foo() == 5)
    @assert(b.bar() == 7)
}

// Interface reassignment with different concrete types.
struct Other
{
    z: s32 = 99
}

impl IFoo for Other
{
    mtd impl foo()->s32 => .z
}

#test
{
    var m: Multi
    var o: Other
    var f: IFoo = cast(IFoo) m
    @assert(f.foo() == 5)
    f = cast(IFoo) o
    @assert(f.foo() == 99)
}

// Interface as function return value.
#test
{
    var f = makeFoo()
    @assert(f.foo() == 5)
    var b = makeBar()
    @assert(b.bar() == 7)
}

// Interface passed to a function.
func callFoo(f: IFoo)->s32
{
    return f.foo()
}

#test
{
    var m: Multi
    @assert(callFoo(cast(IFoo) m) == 5)

    var o: Other
    @assert(callFoo(cast(IFoo) o) == 99)
}
