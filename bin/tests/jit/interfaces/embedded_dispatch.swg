#global fileprivate

interface IDispatch
{
    mtd get()->s32;
}

struct Base
{
    itf:   IDispatch
    value: s32 = 10
}

impl IDispatch for Base
{
    mtd impl get()->s32 => .value
}

struct Child
{
    using base: Base
    valueChild: s32 = 20
}

impl IDispatch for Child
{
    mtd impl get()->s32 => .valueChild
}

func dispatch(base: *Base)->s32
{
    return base.itf.get()
}

func runEmbeddedDispatch()->bool
{
    var base: Base
    base.itf = cast(IDispatch) base

    var child: Child
    child.itf = cast(IDispatch) child

    return dispatch(&base) == 10 and dispatch(&child.base) == 20
}

#test
{
    const ok = #run runEmbeddedDispatch()
    #assert(ok)
}
