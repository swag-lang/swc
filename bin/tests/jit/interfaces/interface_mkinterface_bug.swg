// @BUG @mkinterface still triggers an internal error during front-end analysis, but std registration paths depend on it.
#global skip
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
    actions[0] = @mkinterface(null, #typeof(UndoAction{}), IAction)
    actions[1] = @mkinterface(null, #typeof(RedoAction{}), IAction)

    return actions[0].accept(1) and actions[1].execute(3) == 83
}

#test
{
    const ok = #run runActionRegistry()
    #assert(ok)
}
