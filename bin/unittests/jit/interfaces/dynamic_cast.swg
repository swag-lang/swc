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
    let asMid      = cast(*Mid?, derivedPtr)
    let asBase     = cast(*Base?, derivedPtr)
    if not (derivedPtr is Derived) or not (derivedPtr is Mid) or not (derivedPtr is Base)
    {
        return false
    }
    if (derivedPtr is PointerWrapper)
    {
        return false
    }
    if asMid == null or asBase == null
    {
        return false
    }
    if asMid != &derived.mid or asBase != &derived.mid.base
    {
        return false
    }

    var base        = Base{value: 77}
    var wrapper     = PointerWrapper{base: &base}
    let wrapperPtr  = &wrapper
    let wrappedBase = catch cast(*Base?, wrapperPtr) orelse null
    if not (wrapperPtr is Base) or wrappedBase != &base
    {
        return false
    }

    let itf: INode = derived
    let itfBase    = catch cast(*Base?, itf) orelse null
    if not (itf is Derived) or not (itf is Mid) or not (itf is Base)
    {
        return false
    }
    if (itf is PointerWrapper)
    {
        return false
    }
    if itf.buffer == null
    {
        return false
    }
    if itfBase == null or itfBase.value != 10
    {
        return false
    }

    let dyn: any = derived
    let dynBase  = catch cast(*Base?, dyn) orelse null
    if not (dyn is Derived) or not (dyn is Base)
    {
        return false
    }
    if (dyn is PointerWrapper)
    {
        return false
    }
    if dynBase == null or dynBase.value != 10
    {
        return false
    }

    let notStruct: any = 33
    if (notStruct is Base)
    {
        return false
    }
    if notStruct is Base
    {
        return false
    }

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

    if not (derivedType is baseType) or not (derivedType is midType) or not (s32 is intType)
    {
        return false
    }
    if intType is stringType
    {
        return false
    }

    let intView = catch cast(any?, cast(intType, &number)) orelse null
    if intView == null
    {
        return false
    }

    let baseView = catch cast(any?, cast(baseType, &derived)) orelse null
    if baseView == null
    {
        return false
    }

    let intPtr  = catch cast(*s32?, intView) orelse null
    let basePtr = catch cast(*Base?, baseView) orelse null
    if intPtr == null or intPtr != &number or intPtr[] != 45
    {
        return false
    }
    let boolType: typeinfo = bool
    if &number is boolType
    {
        return false
    }
    if basePtr != &derived.mid.base
    {
        return false
    }

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
