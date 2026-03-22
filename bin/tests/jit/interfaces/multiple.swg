#global fileprivate

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

struct Other
{
    z: s32 = 99
}

impl IFoo for Other
{
    mtd impl foo()->s32 => .z
}

func runMultipleInterfaces()->bool
{
    var m: Multi
    var f = cast(IFoo) m
    var b = cast(IBar) m
    return f.foo() == 5 and b.bar() == 7
}

func runReassignment()->bool
{
    var m: Multi
    var o: Other
    var f: IFoo = cast(IFoo) m
    if f.foo() != 5 do
        return false
    f = cast(IFoo) o
    return f.foo() == 99
}

func makeFoo()->IFoo
{
    var m: Multi
    return cast(IFoo) m
}

func runReturnValue()->bool
{
    var f = makeFoo()
    return f.foo() == 5
}

func callFoo(f: IFoo)->s32
{
    return f.foo()
}

func runParameter()->bool
{
    var m: Multi
    var o: Other
    return callFoo(cast(IFoo) m) == 5 and callFoo(cast(IFoo) o) == 99
}

#test
{
    const ok0 = #run runMultipleInterfaces()
    #assert(ok0)
}

#test
{
    const ok1 = #run runReassignment()
    #assert(ok1)
}

#test
{
    const ok2 = #run runReturnValue()
    #assert(ok2)
}

#test
{
    const ok3 = #run runParameter()
    #assert(ok3)
}
