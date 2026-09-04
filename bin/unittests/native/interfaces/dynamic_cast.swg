#global private

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

func runIntrinsicDynamicTypeInfo()->bool
{
    let baseType:    typeinfo = Base
    let midType:     typeinfo = Mid
    let derivedType: typeinfo = Derived
    let intType:     typeinfo = s32
    let stringType:  typeinfo = string

    var number  = 45
    var derived = Derived{}

    if !Swag.typeIs(baseType, derivedType) or !Swag.typeIs(midType, derivedType) or !Swag.typeIs(intType, s32) do
        return false
    if Swag.typeIs(stringType, intType) do
        return false

    let intRaw = Swag.typeAs(intType, s32, &number)
    if intRaw == null do
        return false

    let baseRaw = Swag.typeAs(baseType, derivedType, &derived)
    if baseRaw == null do
        return false

    let strictDerivedPtr = cast(DynamicCastStrictDerivedPtr) &derived
    let strictBaseRaw    = Swag.typeAs(baseType, derivedType, strictDerivedPtr)
    if strictBaseRaw == null do
        return false

    let intPtr        = cast(*s32?) intRaw
    let basePtr       = cast(*Base?) baseRaw
    let strictBasePtr = cast(*Base?) strictBaseRaw
    if intPtr != &number or intPtr[] != 45 do
        return false
    if Swag.typeAs(bool, intType, &number) != null do
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
    let asMid      = derivedPtr as Mid
    let asBase     = derivedPtr as Base
    Swag.assert(derivedPtr is Derived)
    Swag.assert(derivedPtr is Mid)
    Swag.assert(derivedPtr is Base)
    Swag.assert(!derivedPtr is PointerWrapper)
    Swag.assert(asMid == &derived.mid)
    Swag.assert(asBase == &derived.mid.base)

    var base        = Base{value: 77}
    var wrapper     = PointerWrapper{base: &base}
    let wrapperPtr  = &wrapper
    let wrappedBase = wrapperPtr as Base
    Swag.assert(wrapperPtr is Base)
    Swag.assert(wrappedBase == &base)

    let itf: INode = derived
    let itfBase    = itf as Base
    Swag.assert(itf is Derived)
    Swag.assert(itf is Mid)
    Swag.assert(itf is Base)
    Swag.assert(!itf is PointerWrapper)
    Swag.assert(itf.buffer != null)
    Swag.assert(itfBase != null)
    Swag.assert(itfBase!.value == 10)

    let dyn: any = derived
    let dynBase  = dyn as Base
    Swag.assert(dyn is Derived)
    Swag.assert(dyn is Base)
    Swag.assert(!dyn is PointerWrapper)
    Swag.assert(dynBase != null)
    Swag.assert(dynBase!.value == 10)

    let notStruct: any = 33
    Swag.assert(!notStruct is Base)
    Swag.assert(notStruct as Base == null)
}

#test
{
    Swag.assert(runIntrinsicDynamicTypeInfo())
}
