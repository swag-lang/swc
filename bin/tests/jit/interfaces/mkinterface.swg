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
    let nullUndo = @mkinterface(null, #typeof(UndoAction), IAction)
    if @kindof(nullUndo) != UndoAction do
        return false
    if @dataof(nullUndo) != null do
        return false

    var actions: [2] IAction
    actions[0] = @mkinterface(null, #typeof(UndoAction), IAction)
    actions[1] = @mkinterface(null, #typeof(RedoAction), IAction)

    if @kindof(actions[0]) != UndoAction or @kindof(actions[1]) != RedoAction do
        return false
    if @dataof(actions[0]) != null or @dataof(actions[1]) != null do
        return false
    if @tableof(actions[0]) == null or @tableof(actions[1]) == null do
        return false
    if @tableof(actions[0]) != @tableof(nullUndo) do
        return false

    var undo: UndoAction
    let castUndo: IAction = undo
    if @kindof(castUndo) != UndoAction do
        return false
    if @dataof(castUndo) == null do
        return false
    if @tableof(castUndo) != @tableof(actions[0]) do
        return false

    return actions[0].accept(1) and actions[1].execute(3) == 83
}

#test
{
    const ok = #run runActionRegistry()
    #assert(ok)
}
