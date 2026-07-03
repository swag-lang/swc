#global private

struct NullDerefItem
{
    x: s32
    y: s32
}

#[Swag.Safety(.Null, false)]
func nullSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Null)
}

#[Swag.Safety(.Null, true)]
func nullSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Null)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Null ? true : false
    #assert(#safety(Swag.SafetyWhat.Null) == expected)
}

// ---------------------------------------------------------------------------
// Provable null dereferences: each is reported and its function's codegen is
// aborted, so the faulty code is never executed.
// ---------------------------------------------------------------------------

// Store through a null pointer.
#test
{
    var p: #null *NullDerefItem = null
    p.x = 1 // swc-expected-error {{safety_err_null_deref}}
}

// Store into a non-first field (non-zero offset) of a null pointer.
#test
{
    var p: #null *NullDerefItem = null
    p.y = 2 // swc-expected-error {{safety_err_null_deref}}
}

// Read a field through a null pointer.
#test
{
    var p: #null *NullDerefItem = null
    let v = p.x // swc-expected-error {{safety_err_null_deref}}
    discard v
}

// Taking the address of a field requires the pointer to be valid.
#test
{
    var p: #null *NullDerefItem = null
    let q = &p.x // swc-expected-error {{safety_err_null_deref}}
    discard q
}

// Dereference of a null scalar pointer.
#test
{
    var p: #null *s32 = null
    let v = dref p // swc-expected-error {{safety_err_null_deref}}
    discard v
}

// The null value propagates through a copy.
#test
{
    var p: #null *NullDerefItem = null
    var q = p
    q.x = 3 // swc-expected-error {{safety_err_null_deref}}
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

// Real pointer to a local.
#test
{
    var v: NullDerefItem
    var p: *NullDerefItem = &v
    p.x = 42
    @assert(v.x == 42)
}

// Null pointer reassigned to a real local before any use.
#test
{
    var w: NullDerefItem
    var p: #null *NullDerefItem = null
    p = &w
    p.x = 7
    @assert(w.x == 7)
}

// Copy of a valid pointer.
#test
{
    var v: NullDerefItem
    var p = &v
    var q = p
    q.y = 11
    @assert(v.y == 11)
}

// An unknown (parameter) pointer is never assumed null: no false positive.
func writeThroughParam(p: *NullDerefItem)
{
    p.x = 99
}

#test
{
    var v: NullDerefItem
    writeThroughParam(&v)
    @assert(v.x == 99)
}
