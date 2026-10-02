#global private

struct IndirectContentsValue
{
    pointer: *s32?
    count:   u64
}

var indirectContentsGlobal        = 31
var indirectContentsGlobalCarrier = IndirectContentsValue{pointer: &indirectContentsGlobal, count: 2}
var indirectContentsSaved:     IndirectContentsValue
var indirectContentsSavedSlot: *IndirectContentsValue?

#[Swag.NoInline]
func indirectContentsCopy(destination: *IndirectContentsValue, source: *IndirectContentsValue)
{
    destination[] = source[]
}

#[Swag.NoInline]
func indirectContentsByValue(destination: *IndirectContentsValue, value: IndirectContentsValue)
{
    indirectContentsCopy(destination, &value)
}

#[Swag.NoInline]
func indirectContentsRead(source: *IndirectContentsValue)->IndirectContentsValue => source[]

#[Swag.NoInline]
func indirectContentsIdentity(source: *IndirectContentsValue)->*IndirectContentsValue => source

#[Swag.NoInline]
func indirectContentsKeepValue(value: IndirectContentsValue)
{
    indirectContentsSaved = value
}

#[Swag.NoInline]
func indirectContentsKeepSlot(source: *IndirectContentsValue)
{
    indirectContentsSavedSlot = source
}

// The intermediate parameter slot dies, while the copied field still names a global.
#test
{
    var value = IndirectContentsValue{pointer: &indirectContentsGlobal, count: 1}
    indirectContentsByValue(&indirectContentsSaved, value)
    Swag.assert(indirectContentsSaved.pointer == &indirectContentsGlobal)
    Swag.assert(indirectContentsSaved.count == 1)
    let copied = indirectContentsRead(&value)
    Swag.assert(copied.pointer == &indirectContentsGlobal)
    var destination: IndirectContentsValue
    indirectContentsCopy(&destination, &indirectContentsGlobalCarrier)
    Swag.assert(destination.pointer == &indirectContentsGlobal)
    Swag.assert(destination.count == 2)
}

// These unsafe paths are definitions only. Copying contents must preserve their lifetime.
func indirectContentsRejectPointee()
{
    var local = 7
    var value = IndirectContentsValue{pointer: &local, count: 1}
    indirectContentsByValue(&indirectContentsSaved, value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func indirectContentsRejectParameterSlot(value: IndirectContentsValue)
{
    indirectContentsKeepSlot(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func indirectContentsRejectReturnedCopy()->IndirectContentsValue
{
    var local = 7
    var value = IndirectContentsValue{pointer: &local, count: 1}
    let copy  = indirectContentsRead(&value)
    return copy     // swc-expected-error {{sanity_err_borrow_escape}}
}

func indirectContentsRejectNestedCopy()
{
    var local = 7
    var value = IndirectContentsValue{pointer: &local, count: 1}
    indirectContentsKeepValue(indirectContentsRead(&value))     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Opaque pointer results retain a conservative input-lifetime bound: a may-alias
// return bit does not prove that every returned object is exactly the input slot.
func indirectContentsRejectNestedPointer()
{
    var local = 7
    var value = IndirectContentsValue{pointer: &local, count: 1}
    indirectContentsCopy(&indirectContentsSaved, indirectContentsIdentity(&value))     // swc-expected-error {{sanity_err_borrow_escape}}
}

func indirectContentsRejectPointerSnapshot()
{
    var local   = 7
    var value   = IndirectContentsValue{pointer: &local, count: 1}
    let pointer = indirectContentsIdentity(&value)
    indirectContentsCopy(&indirectContentsSaved, pointer)     // swc-expected-error {{sanity_err_borrow_escape}}
}
