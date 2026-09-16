#global private

#[Swag.DynCast]
struct Base
{
    value: s32 = 10
}

struct Mid
{
    using base: Base
    midValue:   s32 = 20
}

struct Derived
{
    using mid:    Mid
    derivedValue: s32 = 30
}

struct PointerWrapper
{
    using base:   *Base
    wrapperValue: s32 = 40
}

interface INode {}

impl INode for Derived {}

func runDynamicStructCast()->bool
{
    var derived = Derived{}

    let derivedPtr = &derived
    let asMid      = cast #try (*Mid) derivedPtr
    let asBase     = cast #try (*Base) derivedPtr
    if not (derivedPtr is Derived) or not (derivedPtr is Mid) or not (derivedPtr is Base) do
        return false
    if (derivedPtr is PointerWrapper) do
        return false
    if asMid == null or asBase == null do
        return false
    if asMid != &derived.mid or asBase != &derived.mid.base do
        return false

    var base        = Base{value: 77}
    var wrapper     = PointerWrapper{base: &base}
    let wrapperPtr  = &wrapper
    let wrappedBase = cast #try (*Base) wrapperPtr
    if not (wrapperPtr is Base) or wrappedBase != &base do
        return false

    let itf: INode = derived
    let itfBase    = cast #try (*Base) itf
    if not (itf is Derived) or not (itf is Mid) or not (itf is Base) do
        return false
    if (itf is PointerWrapper) do
        return false
    if itf.buffer == null do
        return false
    if itfBase == null or itfBase.value != 10 do
        return false

    let dyn: any = derived
    let dynBase  = cast #try (*Base) dyn
    if not (dyn is Derived) or not (dyn is Base) do
        return false
    if (dyn is PointerWrapper) do
        return false
    if dynBase == null or dynBase.value != 10 do
        return false

    let notStruct: any = 33
    if (notStruct is Base) do
        return false
    if notStruct is Base do
        return false

    return true
}

func runRuntimeTargetCasts()->bool
{
    let baseType:    typeinfo = Base
    let midType:     typeinfo = Mid
    let derivedType: typeinfo = Derived
    let intType:     typeinfo = s32
    let stringType:  typeinfo = string

    var number  = 45
    var derived = Derived{}

    if not (derivedType is baseType) or not (derivedType is midType) or not (s32 is intType) do
        return false
    if intType is stringType do
        return false

    let intView = cast #try(intType) &number
    if intView == null do
        return false

    let baseView = cast #try(baseType) &derived
    if baseView == null do
        return false

    let intPtr  = cast #try(*s32) intView
    let basePtr = cast #try(*Base) baseView
    if intPtr == null or intPtr != &number or intPtr[] != 45 do
        return false
    let boolType: typeinfo = bool
    if &number is boolType do
        return false
    if basePtr != &derived.mid.base do
        return false

    return true
}

#test
{
    const ok = #run runDynamicStructCast()
    #assert(ok)
}

#test
{
    const ok = #run runRuntimeTargetCasts()
    #assert(ok)
}
