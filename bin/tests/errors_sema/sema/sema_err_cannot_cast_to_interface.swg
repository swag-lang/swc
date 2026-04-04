// Regression test for @mkinterface during front-end analysis.
#global fileprivate

interface IAction
{
    mtd accept(id: s32)->bool;
    mtd execute(id: s32)->s32;
}

struct UndoAction {}
struct RedoAction {}
struct MissingAction {}

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

var missing = @mkinterface(null, MissingAction, IAction) // swc-expected-error {{sema_err_cannot_cast_to_interface}}

#test
{
    var actions: [2] IAction
    actions[0] = @mkinterface(null, #typeof(UndoAction{}), IAction)
    actions[1] = @mkinterface(null, #typeof(RedoAction{}), IAction)

    discard actions[0].accept(1)
    discard actions[1].execute(3)
}
