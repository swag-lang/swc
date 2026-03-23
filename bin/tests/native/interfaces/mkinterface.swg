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

func validateRuntimeInterface(itf: IAction, expectedType: const *Swag.TypeInfoStruct, expectNullObject: bool)->bool
{
    let runtimeItf = cast(*Swag.Interface) &itf
    if runtimeItf == null or runtimeItf.itable == null do
        return false

    let kind      = cast(const *Swag.TypeInfoStruct) @kindof(itf)
    let tableType = cast(const *Swag.TypeInfoStruct) dref runtimeItf.itable
    if kind != expectedType or tableType != expectedType do
        return false

    if expectNullObject do
        return runtimeItf.obj == null

    return runtimeItf.obj != null and runtimeItf.obj != cast(*void) runtimeItf
}

#test
{
    var actions: [2] IAction
    actions[0] = @mkinterface(null, #typeof(UndoAction{}), IAction)
    actions[1] = @mkinterface(null, #typeof(RedoAction{}), IAction)

    @assert(actions[0].accept(1))
    @assert(actions[1].execute(3) == 83)
    @assert(validateRuntimeInterface(actions[0], cast(const *Swag.TypeInfoStruct) #typeof(UndoAction{}), true))
    @assert(validateRuntimeInterface(actions[1], cast(const *Swag.TypeInfoStruct) #typeof(RedoAction{}), true))

    var local = UndoAction{}
    var castAction: IAction = local
    @assert(validateRuntimeInterface(castAction, cast(const *Swag.TypeInfoStruct) #typeof(UndoAction{}), false))
}
