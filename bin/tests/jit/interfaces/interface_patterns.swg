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

func runActionRegistry()->bool
{
    var actions: [2] IAction
    var undo: UndoAction
    var redo: RedoAction
    actions[0] = cast(IAction) undo
    actions[1] = cast(IAction) redo

    return actions[0].accept(1) and
           !actions[0].accept(2) and
           actions[0].execute(2) == 42 and
           actions[1].accept(2) and
           !actions[1].accept(1) and
           actions[1].execute(3) == 83
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
    const ok = #run runActionRegistry()
    #assert(ok)
}

#test
{
    const ok = #run runEmbeddedDispatch()
    #assert(ok)
}
