#global fileprivate

interface IAction
{
    mtd accept(id: s32)->bool;
    mtd execute(id: s32)->s32;
}

struct UndoAction {}
struct RedoAction {}

impl IAction for UndoAction
{
    mtd impl accept(id: s32)->bool => id == 1
    mtd impl execute(id: s32)->s32 => id + 40
}

impl IAction for RedoAction
{
    mtd impl accept(id: s32)->bool => id == 2
    mtd impl execute(id: s32)->s32 => id + 80
}

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

#test
{
    var actions: [2] IAction
    var undo: UndoAction
    var redo: RedoAction
    actions[0] = cast(IAction) undo
    actions[1] = cast(IAction) redo

    @assert(actions[0].accept(1))
    @assert(!actions[0].accept(2))
    @assert(actions[0].execute(2) == 42)
    @assert(actions[1].accept(2))
    @assert(!actions[1].accept(1))
    @assert(actions[1].execute(3) == 83)
}

#test
{
    var base: Base
    base.itf = cast(IDispatch) base
    @assert(dispatch(&base) == 10)

    var child: Child
    child.itf = cast(IDispatch) child
    @assert(dispatch(&child.base) == 20)
}
