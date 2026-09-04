#global private

// A 'late' field defers its initialization: the storage starts null while the
// declared type stays NON-null. Reads are guarded under null safety; a comparison
// with null observes the transition, and the struct remains default-initializable.

struct SemaLateItem
{
    value: s32
}

struct SemaLateBox
{
    late item: *SemaLateItem
    late name: string
    count:     s32
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
    return !(b.item != null)
}

// The field type is plain non-null at every read: no proof, no '!'.
func semaLateTypeIsNonNull(it: *SemaLateItem)->bool
{
    var b: SemaLateBox
    b.item = it
    #assert(#typeof(b.item) == *SemaLateItem)
    let p: *SemaLateItem = b.item
    return p == it
}

// A null comparison observes the set transition without reading the value.
func semaLatePresence(it: *SemaLateItem)->bool
{
    var b: SemaLateBox
    if (b.item != null) do
        return false
    b.item = it
    return (b.item != null)
}

// -----------------------------------------------------------------------------
// Rejected shapes.
// -----------------------------------------------------------------------------

// 'late' only qualifies struct fields.
func semaLateErrLocal()
{
    late var x: *s32     // swc-expected-error {{sema_err_late_not_field}}
    Swag.print(x)
}

// A late field cannot carry an initializer.
struct SemaLateErrInit
{
    late name: string = "x"     // swc-expected-error {{sema_err_late_with_initializer}}
}

// The type must have a null state to borrow as the 'unset' sentinel.
struct SemaLateErrType
{
    late v: s32     // swc-expected-error {{sema_err_late_bad_type}}
}

// 'late' with '?' is a contradiction: late fields are non-null by construction.
struct SemaLateErrNullable
{
    late p: *s32?     // swc-expected-error {{sema_err_late_bad_type}}
}

// A read proven never-assigned on every path is a compile-time fault.
func semaLateErrNeverSet()->*SemaLateItem
{
    var b: SemaLateBox
    return b.item     // swc-expected-error {{sema_err_late_read_never_set}}
}

// Writing THROUGH a late field dereferences it: a read, never an initialization.
func semaLateErrNestedWrite()
{
    var b: SemaLateBox
    b.item.value = 8     // swc-expected-error {{sema_err_late_read_never_set}}
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
    return (b.item != null)
}

// A null comparison before any assignment is not a read.
func semaLateOkPresenceFirst()->bool
{
    var b: SemaLateBox
    return (b.item != null)
}
