#global private

interface IAction
{
    mtd accept(id: s32)->bool
    mtd execute(id: s32)->s32
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

func validateRuntimeInterface(itf: IAction, expectedType: const *Swag.TypeInfoStruct, expectNullObject: bool)->bool
{
    let runtimeItf = cast(*Swag.Interface) &itf
    if runtimeItf == null or runtimeItf.itable == null do
        return false

    let kind      = cast(const *Swag.TypeInfoStruct) Swag.kindOf(itf)
    let tableType = cast(#null const *Swag.TypeInfoStruct) runtimeItf.itable[]
    if kind != expectedType or tableType != expectedType do
        return false

    if expectNullObject do
        return runtimeItf.obj == null

    return runtimeItf.obj != null and runtimeItf.obj != cast(*void) runtimeItf
}

func runActionRegistry()->bool
{
    let actions: [2] IAction = [
        Swag.makeInterface(null, #typeof(UndoAction{}), IAction),
        Swag.makeInterface(null, #typeof(RedoAction{}), IAction)
        ]

    var local               = UndoAction{}
    var castAction: IAction = local

    return actions[0].accept(1) and
           actions[1].execute(3) == 83 and
           validateRuntimeInterface(actions[0], cast(const *Swag.TypeInfoStruct) #typeof(UndoAction{}), true) and
           validateRuntimeInterface(actions[1], cast(const *Swag.TypeInfoStruct) #typeof(RedoAction{}), true) and
           validateRuntimeInterface(castAction, cast(const *Swag.TypeInfoStruct) #typeof(UndoAction{}), false)
}

#test
{
    const ok = #run runActionRegistry()
    #assert(ok)
}
