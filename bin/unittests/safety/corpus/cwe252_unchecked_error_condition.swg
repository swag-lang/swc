#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-252 / CWE-391 - Unchecked return value, unhandled error condition
//
// The call can fail, the caller does not look, and the code after it runs on a value that was
// never produced. In C this is the ignored 'errno' and the unread return code; in Juliet it
// is one of the largest families outside the memory classes.
//
// Swag: a fallible call in a context that cannot handle an error is a compile-time ERROR, not
// a warning. Every failure has to be propagated, caught, dismissed on purpose, or asserted -
// four spellings, all visible. A value-returning call whose result is dropped is rejected too,
// unless the function opts out with '#[Swag.Discardable]'.
// -----------------------------------------------------------------------------

struct LoadError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

func load(present: bool)->s32 fail
{
    if !present do
        fail LoadError{base: Swag.BaseError{"nothing to load"}, code: 7}
    return 1
}

func compute()->s32 => 42

// --- Faults ---

// No handler and no 'fail' on the caller: the error would leave with nothing marking it.
func ignoresFailure()->s32
{
    return load(false)     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

// The result of a value-returning call is dropped silently.
func ignoresResult()
{
    compute()     // swc-expected-error {{sema_err_return_value_must_be_used}}
}

// 'try' needs a context that can propagate.
func propagatesWithoutBeingFallible()->s32
{
    return try load(false)     // swc-expected-error {{sema_err_try_outside_fallible_context}}
}

// --- Sound: the four visible spellings ---

// Propagate, explicitly.
func propagates(present: bool)->s32 fail
{
    return try load(present)
}

// Propagate, implicitly: inside a 'fail' function a fallible call already propagates.
func propagatesImplicitly(present: bool)->s32 fail
{
    return load(present)
}

// Catch and inspect.
func catchesAndInspects(present: bool)->s32
{
    let value = catch load(present) as failure
    if failure != null do
        return -(cast(LoadError) failure).code
    return value
}

// Dismiss on purpose: the type default stands in.
func dismisses(present: bool)->s32
{
    return catch load(present)
}

// Handle on the failure path only: the handler runs instead of the rest, and can divert the
// flow. 'catch ... else' applies to the CALL, so the fallible helper writes its result out.
func loadInto(out: *s32, present: bool) fail
{
    out[] = try load(present)
}

func handlesOnFailure(present: bool)->s32
{
    var result = -1's32
    catch loadInto(&result, present) else do
        result = -2
    return result
}

// Dropping a result on purpose is spelled.
func discardsOnPurpose()
{
    discard compute()
}

#test
{
    Swag.assert((catch propagates(true)) == 1)
    Swag.assert((catch propagatesImplicitly(true)) == 1)
    Swag.assert(catchesAndInspects(true) == 1)
    Swag.assert(catchesAndInspects(false) == -7)
    Swag.assert(dismisses(false) == 0)
    Swag.assert(handlesOnFailure(true) == 1)
    Swag.assert(handlesOnFailure(false) == -2)
    discardsOnPurpose()
}
