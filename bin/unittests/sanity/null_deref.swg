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
    const cfg      = #run dref notnull @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Null ? true : false
    #assert(#safety(Swag.SafetyWhat.Null) == expected)
}

// ---------------------------------------------------------------------------
// Provable null dereferences. Use-site enforcement rejects a raw dereference of a
// still-nullable value at compile time, so each case goes through 'notnull': the
// explicit assertion the programmer can get wrong. With the Assume runtime guard
// disabled, the write really reaches the null pointer, the sanitizer proves it,
// and the function's codegen is aborted. Each is marked `#[Swag.Sanity(.Null,
// true)]` so the sanitizer runs in every build config, including fast-compile
// where the sanity checks are off by default.
// ---------------------------------------------------------------------------

// Store through a null pointer (first field, offset 0).
#[Swag.Safety(.Assume, false), Swag.Sanity(.Null, true)]
#test
{
    var p: #null *NullDerefItem = null
    let q = notnull p
    q.x = 1     // swc-expected-error {{sanity_err_null_deref}}
}

// Store into a non-first field (non-zero offset) of a null pointer.
#[Swag.Safety(.Assume, false), Swag.Sanity(.Null, true)]
#test
{
    var p: #null *NullDerefItem = null
    let q = notnull p
    q.y = 2     // swc-expected-error {{sanity_err_null_deref}}
}

// Store through a null scalar pointer via `dref`.
#[Swag.Safety(.Assume, false), Swag.Sanity(.Null, true)]
#test
{
    var p: #null *s32 = null
    let q = notnull p
    dref q = 9     // swc-expected-error {{sanity_err_null_deref}}
}

// The null value propagates through a copy, then the copy is written through.
#[Swag.Safety(.Assume, false), Swag.Sanity(.Null, true)]
#test
{
    var p: #null *NullDerefItem = null
    var q = notnull p
    q.x = 3     // swc-expected-error {{sanity_err_null_deref}}
}

// A read whose result is actually used (here in an assert) is not dead, so the
// load survives and the null dereference is caught.
#[Swag.Safety(.Assume, false), Swag.Sanity(.Null, true)]
#test
{
    var p: #null *NullDerefItem = null
    let q = notnull p
    @assert(q.x == 0)     // swc-expected-error {{sanity_err_null_deref}}
}

// Path-sensitive: the dereference is inside the branch where the guard proves the
// pointer is null, so it is still reported.
#[Swag.Safety(.Assume, false), Swag.Sanity(.Null, true)]
#test
{
    var p: #null *NullDerefItem = null
    if p == null
    {
        let q = notnull p
        q.x = 4     // swc-expected-error {{sanity_err_null_deref}}
    }
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

// Path-sensitive: the guard makes the dereferencing branch unreachable when the
// pointer is null, so it must NOT be flagged.
#test
{
    var v: NullDerefItem
    var p: #null *NullDerefItem = null
    if p != null
    {
        p.x = 1
    }
    @assert(v.x == 0)
}

// Correlated conditions: the same guard controls both the assignment and the use,
// so the use is only reached when the pointer is non-null. Must NOT be flagged.
// Flow narrowing cannot correlate the two 'if cond' blocks, so the use goes
// through 'notnull'.
func correlatedGuard(cond: bool)
{
    var v: NullDerefItem
    var p: #null *NullDerefItem = null
    if cond
    {
        p = &v
    }
    if cond
    {
        let q = notnull p
        q.x = 5
    }
}

#test
{
    correlatedGuard(true)
    correlatedGuard(false)
}

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
    p   = &w
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
