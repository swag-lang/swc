#global private

// A '#late' field defers its initialization: the storage starts null while the
// declared type stays NON-null. Reads are guarded under null safety, '#isset'
// observes the transition, and the struct remains default-initializable.

struct SemaLateItem
{
    value: s32
}

struct SemaLateBox
{
    item:  #late *SemaLateItem
    name:  #late string
    count: s32
}

// The struct stays default-initializable: late fields default to null storage.
func semaLateDefaultConstructible()->bool
{
    var b: SemaLateBox
    return b.count == 0
}

// A struct literal can omit late fields.
func semaLateLiteralOmits()->bool
{
    let b = SemaLateBox{count: 2}
    return !#isset(b.item)
}

// The field type is plain non-null at every read: no proof, no 'notnull'.
func semaLateTypeIsNonNull(it: *SemaLateItem)->bool
{
    var b: SemaLateBox
    b.item = it
    #assert(#typeof(b.item) == *SemaLateItem)
    let p: *SemaLateItem = b.item
    return p == it
}

// '#isset' observes the set transition.
func semaLateIsSet(it: *SemaLateItem)->bool
{
    var b: SemaLateBox
    if #isset(b.item) do
        return false
    b.item = it
    return #isset(b.item)
}

// -----------------------------------------------------------------------------
// Rejected shapes.
// -----------------------------------------------------------------------------

// '#late' only qualifies struct fields.
func semaLateErrLocal()
{
    var x: #late *s32 // swc-expected-error {{sema_err_late_not_field}}
    @print(x)
}

// A late field cannot carry an initializer.
struct SemaLateErrInit
{
    name: #late string = "x" // swc-expected-error {{sema_err_late_with_initializer}}
}

// The type must have a null state to borrow as the 'unset' sentinel.
struct SemaLateErrType
{
    v: #late s32 // swc-expected-error {{sema_err_late_bad_type}}
}

// '#late #null' is a contradiction: late fields are non-null by construction.
struct SemaLateErrNullable
{
    p: #late #null *s32 // swc-expected-error {{sema_err_late_bad_type}}
}

// A read proven never-assigned on every path is a compile-time fault.
func semaLateErrNeverSet()->*SemaLateItem
{
    var b: SemaLateBox
    return b.item // swc-expected-error {{sema_err_late_read_never_set}}
}

// Writing THROUGH a late field dereferences it: a read, never an initialization.
func semaLateErrNestedWrite()
{
    var b: SemaLateBox
    b.item.value = 8 // swc-expected-error {{sema_err_late_read_never_set}}
}

// A conditional assignment keeps the read legal: the runtime guard covers it.
func semaLateOkMaybeSet(it: *SemaLateItem, use: bool)->s32
{
    var b: SemaLateBox
    if use do
        b.item = it
    return b.item.value
}

// An escaped address may be filled by the callee: no static verdict.
func semaLateFill(slot: **SemaLateItem) {}
func semaLateOkEscaped()->bool
{
    var b: SemaLateBox
    semaLateFill(&b.item)
    return #isset(b.item)
}

// '#isset' before any assignment is not a read.
func semaLateOkIsSetFirst()->bool
{
    var b: SemaLateBox
    return #isset(b.item)
}

// '#isset' only applies to late field accesses.
func semaLateErrIsSetValue(v: s32)->bool
{
    return #isset(v) // swc-expected-error {{sema_err_isset_not_late_field}}
}

func semaLateErrIsSetPlainField(b: *SemaLateBox)->bool
{
    return #isset(b.count) // swc-expected-error {{sema_err_isset_not_late_field}}
}
