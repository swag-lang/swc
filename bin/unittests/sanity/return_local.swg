#global private

// ---------------------------------------------------------------------------
// Returning the address of a local: the frame dies with the return, so the pointer is
// always dangling.
//
// The borrow rules are part of the language and cannot be switched off, so these two
// functions are rejected in sema and never reach codegen. The Memory sanitizer's own
// stack-escape check therefore only ever sees shapes the language rules cannot judge;
// what this file pins is that the rejection happens, and that the valid programs below
// stay accepted with the sanitizer forced on.
// ---------------------------------------------------------------------------

func escapeLocal()->*s32
{
    var v: s32
    return &v     // swc-expected-error {{sanity_err_borrow_escape}}
}

// The address survives a copy before being returned.
func escapeLocalViaCopy()->*s32
{
    var v: s32
    var p = &v
    return p     // swc-expected-error {{sanity_err_borrow_escape}}
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

var GlobalValue: s32

// Address of a global outlives the call.
#[Swag.Sanity(.Memory, true)]
func globalAddress()->*s32
{
    return &GlobalValue
}

#test
{
    let p = globalAddress()
    Swag.assert(p != null)
}

// A pointer received as a parameter is not a frame address.
#[Swag.Sanity(.Memory, true)]
func passThrough(p: *s32)->*s32
{
    return p
}

#test
{
    let p = passThrough(&GlobalValue)
    Swag.assert(p == &GlobalValue)
}
