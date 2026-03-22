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

#test
{
    let nullUndo = @mkinterface(null, UndoAction, IAction)
    @assert(@kindof(nullUndo) == UndoAction)
    @assert(@dataof(nullUndo) == null)

    var actions: [2] IAction
    actions[0] = @mkinterface(null, UndoAction, IAction)
    actions[1] = @mkinterface(null, RedoAction, IAction)

    @assert(@kindof(actions[0]) == UndoAction)
    @assert(@kindof(actions[1]) == RedoAction)
    @assert(@dataof(actions[0]) == null)
    @assert(@dataof(actions[1]) == null)
    @assert(@tableof(actions[0]) != null)
    @assert(@tableof(actions[1]) != null)
    @assert(@tableof(actions[0]) == @tableof(nullUndo))

    var undo: UndoAction
    let castUndo: IAction = undo
    @assert(@kindof(castUndo) == UndoAction)
    @assert(@dataof(castUndo) != null)
    @assert(@tableof(castUndo) == @tableof(actions[0]))
    @assert(actions[0].accept(1))
    @assert(actions[1].execute(3) == 83)
}
