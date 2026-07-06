#global private

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

// Interface as function return value. The returned interface borrows the storage
// it was created from, so that storage must outlive the call: use module storage,
// not a local.
var FooBarStorage: Multi

func makeFoo()->IFoo
{
    return cast(IFoo) FooBarStorage
}

func makeBar()->IBar
{
    return cast(IBar) FooBarStorage
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
