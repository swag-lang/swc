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

#test
{
    var actions: [2] IAction = undefined
    actions[0] = Swag.makeInterface(null, #typeof(UndoAction{}), IAction)
    actions[1] = Swag.makeInterface(null, #typeof(RedoAction{}), IAction)

    Swag.assert(actions[0].accept(1))
    Swag.assert(actions[1].execute(3) == 83)
    Swag.assert(validateRuntimeInterface(actions[0], cast(const *Swag.TypeInfoStruct) #typeof(UndoAction{}), true))
    Swag.assert(validateRuntimeInterface(actions[1], cast(const *Swag.TypeInfoStruct) #typeof(RedoAction{}), true))

    var local               = UndoAction{}
    var castAction: IAction = local
    Swag.assert(validateRuntimeInterface(castAction, cast(const *Swag.TypeInfoStruct) #typeof(UndoAction{}), false))

    let constPtr: const *UndoAction = &local
    let constAction                 = Swag.makeInterface(constPtr, UndoAction, IAction)
    let rawConst                    = cast(const *UndoAction) constAction.buffer
    #assert(#typeof(constAction) == const IAction)
    Swag.assert(rawConst == constPtr)

    let constFromDeref: const IAction = constPtr[]
    let rawFromDeref = cast(const *UndoAction) constFromDeref.buffer
    #assert(#typeof(constFromDeref) == const IAction)
    Swag.assert(rawFromDeref != null)

    let constRef: const *UndoAction = &local
    let constFromRef                = Swag.makeInterface(constRef, UndoAction, IAction)
    let rawFromRef                  = cast(const *UndoAction) constFromRef.buffer
    #assert(#typeof(constFromRef) == const IAction)
    Swag.assert(rawFromRef == constPtr)

    let boxedConstAction   = Swag.makeAny(&constAction, const IAction)
    let unboxedConstAction = cast(const IAction) boxedConstAction
    let rawUnboxedConst    = cast(const *UndoAction) unboxedConstAction.buffer
    #assert(#typeof(unboxedConstAction) == const IAction)
    Swag.assert(rawUnboxedConst == constPtr)

    let constFromValue: const IAction = local
    #assert(#typeof(constFromValue) == const IAction)
}
