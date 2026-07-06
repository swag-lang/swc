#global private

// ---------------------------------------------------------------------------
// Calling through a function pointer proven to be null (a never-assigned lambda or
// closure) faults just like dereferencing a null data pointer. Marked
// `#[Swag.Sanity(.Null, true)]` so the sanitizer runs (and catches it) in every config.
// ---------------------------------------------------------------------------

#[Swag.Sanity(.Null, true)]
#test
{
    var f: func()->s32
    let x = f() // swc-expected-error {{sanity_err_null_call}}
    discard x
}

// The null value propagates through a copy.
#[Swag.Sanity(.Null, true)]
#test
{
    var f: func()->s32
    var g = f
    let x = g() // swc-expected-error {{sanity_err_null_call}}
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
