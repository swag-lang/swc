#global fileprivate

struct Base
{
    value: s32 = 10
}

struct Mid
{
    using base: Base
    midValue: s32 = 20
}

struct Derived
{
    using mid: Mid
    derivedValue: s32 = 30
}

struct PointerWrapper
{
    using base: *Base
    wrapperValue: s32 = 40
}

interface INode
{
}

impl INode for Derived
{
}

func runDynamicStructCast()->bool
{
    var derived = Derived{}

    let derivedPtr = &derived
    let asMid      = derivedPtr as Mid
    let asBase     = derivedPtr as Base
    if !derivedPtr is Derived or !derivedPtr is Mid or !derivedPtr is Base do
        return false
    if derivedPtr is PointerWrapper do
        return false
    if asMid == null or asBase == null do
        return false
    if asMid != &derived.mid or asBase != &derived.mid.base do
        return false

    var base    = Base{value: 77}
    var wrapper = PointerWrapper{base: &base}
    let wrapperPtr  = &wrapper
    let wrappedBase = wrapperPtr as Base
    if !wrapperPtr is Base or wrappedBase != &base do
        return false

    let itf: INode = derived
    let itfBase    = itf as Base
    if !itf is Derived or !itf is Mid or !itf is Base do
        return false
    if itf is PointerWrapper do
        return false
    if @dataof(itf) == null do
        return false
    if itfBase == null or itfBase.value != 10 do
        return false

    let dyn: any = derived
    let dynBase  = dyn as Base
    if !dyn is Derived or !dyn is Base do
        return false
    if dyn is PointerWrapper do
        return false
    if dynBase == null or dynBase.value != 10 do
        return false

    let notStruct: any = 33
    if notStruct is Base do
        return false
    if notStruct as Base != null do
        return false

    return true
}

#test
{
    const ok = #run runDynamicStructCast()
    #assert(ok)
}
