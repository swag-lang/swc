#global private

// ---------------------------------------------------------------------------
// Returning the address of a local: the frame dies with the return, so the pointer is
// always dangling. Marked `#[Swag.Safety(.Memory, true)]` so the sanitizer runs (and
// catches it) in every build config.
// ---------------------------------------------------------------------------

#[Swag.Safety(.Memory, true)]
func escapeLocal()->*s32
{
    var v: s32
    return &v // swc-expected-error {{safety_err_return_local_address}}
}

#test
{
    let p = escapeLocal()
    discard p
}

// The address survives a copy before being returned.
#[Swag.Safety(.Memory, true)]
func escapeLocalViaCopy()->*s32
{
    var v: s32
    var p = &v
    return p // swc-expected-error {{safety_err_return_local_address}}
}

#test
{
    let p = escapeLocalViaCopy()
    discard p
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

var GlobalValue: s32

// Address of a global outlives the call.
#[Swag.Safety(.Memory, true)]
func globalAddress()->*s32
{
    return &GlobalValue
}

#test
{
    let p = globalAddress()
    @assert(p != null)
}

// A pointer received as a parameter is not a frame address.
#[Swag.Safety(.Memory, true)]
func passThrough(p: *s32)->*s32
{
    return p
}

#test
{
    let p = passThrough(&GlobalValue)
    @assert(p == &GlobalValue)
}
