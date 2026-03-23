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

#test
{
    var derived = Derived{}

    let derivedPtr = &derived
    let asMid      = derivedPtr as Mid
    let asBase     = derivedPtr as Base
    @assert(derivedPtr is Derived)
    @assert(derivedPtr is Mid)
    @assert(derivedPtr is Base)
    @assert(!derivedPtr is PointerWrapper)
    @assert(asMid == &derived.mid)
    @assert(asBase == &derived.mid.base)

    var base    = Base{value: 77}
    var wrapper = PointerWrapper{base: &base}
    let wrapperPtr  = &wrapper
    let wrappedBase = wrapperPtr as Base
    @assert(wrapperPtr is Base)
    @assert(wrappedBase == &base)

    let itf: INode = derived
    let itfBase    = itf as Base
    @assert(itf is Derived)
    @assert(itf is Mid)
    @assert(itf is Base)
    @assert(!itf is PointerWrapper)
    @assert(@dataof(itf) != null)
    @assert(itfBase != null)
    @assert(itfBase.value == 10)

    let dyn: any = derived
    let dynBase  = dyn as Base
    @assert(dyn is Derived)
    @assert(dyn is Base)
    @assert(!dyn is PointerWrapper)
    @assert(dynBase != null)
    @assert(dynBase.value == 10)

    let notStruct: any = 33
    @assert(!notStruct is Base)
    @assert(notStruct as Base == null)
}
