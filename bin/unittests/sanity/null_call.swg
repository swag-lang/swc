#global private

// ---------------------------------------------------------------------------
// Calling through a function pointer proven to be null (a never-assigned lambda or
// closure) faults just like dereferencing a null data pointer. Use-site enforcement
// rejects the raw call at compile time, so each case asserts with 'notnull' (the
// explicit assertion the programmer can get wrong) and disables the Assume runtime
// guard so the call really reaches the null pointer. Marked
// `#[Swag.Sanity(.Null, true)]` so the sanitizer runs (and catches it) in every config.
// ---------------------------------------------------------------------------

#[Swag.Safety(.Assume, false), Swag.Sanity(.Null, true)]
#test
{
    var f: #null func()->s32
    let g = notnull f
    let x = g()     // swc-expected-error {{sanity_err_null_call}}
    discard x
}

// The null value propagates through a copy.
#[Swag.Safety(.Assume, false), Swag.Sanity(.Null, true)]
#test
{
    var f: #null func()->s32
    var g = f
    let h = notnull g
    let x = h()     // swc-expected-error {{sanity_err_null_call}}
    discard x
}

// ---------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// ---------------------------------------------------------------------------

func giveSeven()->s32
{
    return 7
}

#test
{
    var f = &giveSeven
    @assert(f() == 7)
}

// A function pointer received as a parameter is not assumed null.
func callIt(f: func()->s32)->s32
{
    return f()
}

#test
{
    @assert(callIt(&giveSeven) == 7)
}
