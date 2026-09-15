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

#[Swag.Strict]
alias DynamicCastStrictDerivedPtr = *Derived

func runRuntimeTargetCasts()->bool
{
    let baseType:    typeinfo = Base
    let midType:     typeinfo = Mid
    let derivedType: typeinfo = Derived
    let intType:     typeinfo = s32
    let stringType:  typeinfo = string

    var number  = 45
    var derived = Derived{}

    if cast #try(baseType) derivedType == null or cast #try(midType) derivedType == null or cast #try(intType) s32 == null do
        return false
    if cast #try(stringType) intType != null do
        return false

    let intView = cast #try(intType) &number
    if intView == null do
        return false

    let baseView = cast #try(baseType) &derived
    if baseView == null do
        return false

    let strictDerivedPtr = cast(DynamicCastStrictDerivedPtr) &derived
    let strictBaseView   = cast #try(baseType) cast(*Derived) strictDerivedPtr
    if strictBaseView == null do
        return false

    let intPtr        = cast #try(*s32) intView
    let basePtr       = cast #try(*Base) baseView
    let strictBasePtr = cast #try(*Base) strictBaseView
    if intPtr == null or intPtr != &number or intPtr[] != 45 do
        return false
    let boolType: typeinfo = bool
    if cast #try(boolType) &number != null do
        return false
    if basePtr != &derived.mid.base do
        return false
    if strictBasePtr != &derived.mid.base do
        return false

    return true
}

#test
{
    var derived = Derived{}

    let derivedPtr = &derived
    let asMid      = cast #try (*Mid) derivedPtr
    let asBase     = cast #try (*Base) derivedPtr
    Swag.assert((cast #try (*Derived) derivedPtr != null))
    Swag.assert((cast #try (*Mid) derivedPtr != null))
    Swag.assert((cast #try (*Base) derivedPtr != null))
    Swag.assert(not (cast #try (*PointerWrapper) derivedPtr != null))
    Swag.assert(asMid == &derived.mid)
    Swag.assert(asBase == &derived.mid.base)

    var base        = Base{value: 77}
    var wrapper     = PointerWrapper{base: &base}
    let wrapperPtr  = &wrapper
    let wrappedBase = cast #try (*Base) wrapperPtr
    Swag.assert((cast #try (*Base) wrapperPtr != null))
    Swag.assert(wrappedBase == &base)

    let itf: INode = derived
    let itfBase    = cast #try (*Base) itf
    Swag.assert((cast #try (*Derived) itf != null))
    Swag.assert((cast #try (*Mid) itf != null))
    Swag.assert((cast #try (*Base) itf != null))
    Swag.assert(not (cast #try (*PointerWrapper) itf != null))
    Swag.assert(itf.buffer != null)
    Swag.assert(itfBase != null)
    Swag.assert(itfBase.value == 10)

    let dyn: any = derived
    let dynBase  = cast #try (*Base) dyn
    Swag.assert((cast #try (*Derived) dyn != null))
    Swag.assert((cast #try (*Base) dyn != null))
    Swag.assert(not (cast #try (*PointerWrapper) dyn != null))
    Swag.assert(dynBase != null)
    Swag.assert(dynBase.value == 10)

    let notStruct: any = 33
    Swag.assert(not (cast #try (*Base) notStruct != null))
    Swag.assert(cast #try (*Base) notStruct == null)
}

#test
{
    Swag.assert(runRuntimeTargetCasts())
}
