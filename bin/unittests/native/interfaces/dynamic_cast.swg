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

    if not (derivedType is baseType) or not (derivedType is midType) or not (s32 is intType) do
        return false
    if intType is stringType do
        return false

    let intView = catch cast(any?, cast(intType, &number))
    if intView == null do
        return false

    let baseView = catch cast(any?, cast(baseType, &derived))
    if baseView == null do
        return false

    let strictDerivedPtr = cast(DynamicCastStrictDerivedPtr, &derived)
    let strictBaseView   = catch cast(any?, cast(baseType, cast(*Derived, strictDerivedPtr)))
    if strictBaseView == null do
        return false

    let intPtr        = catch cast(*s32?, intView)
    let basePtr       = catch cast(*Base?, baseView)
    let strictBasePtr = catch cast(*Base?, strictBaseView)
    if intPtr == null or intPtr != &number or intPtr[] != 45 do
        return false
    let boolType: typeinfo = bool
    if &number is boolType do
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
    let asMid      = cast(*Mid?, derivedPtr)
    let asBase     = cast(*Base?, derivedPtr)
    Swag.assert((derivedPtr is Derived))
    Swag.assert((derivedPtr is Mid))
    Swag.assert((derivedPtr is Base))
    Swag.assert(not (derivedPtr is PointerWrapper))
    Swag.assert(asMid == &derived.mid)
    Swag.assert(asBase == &derived.mid.base)

    var base        = Base{value: 77}
    var wrapper     = PointerWrapper{base: &base}
    let wrapperPtr  = &wrapper
    let wrappedBase = catch cast(*Base?, wrapperPtr)
    Swag.assert((wrapperPtr is Base))
    Swag.assert(wrappedBase == &base)

    let itf: INode = derived
    let itfBase    = catch cast(*Base?, itf)
    Swag.assert((itf is Derived))
    Swag.assert((itf is Mid))
    Swag.assert((itf is Base))
    Swag.assert(not (itf is PointerWrapper))
    Swag.assert(itf.buffer != null)
    Swag.assert(itfBase != null)
    Swag.assert(itfBase.value == 10)

    let dyn: any = derived
    let dynBase  = catch cast(*Base?, dyn)
    Swag.assert((dyn is Derived))
    Swag.assert((dyn is Base))
    Swag.assert(not (dyn is PointerWrapper))
    Swag.assert(dynBase != null)
    Swag.assert(dynBase.value == 10)

    let notStruct: any = 33
    Swag.assert(not (notStruct is Base))
    Swag.assert(not (notStruct is Base))
}

#test
{
    Swag.assert(runRuntimeTargetCasts())
}
