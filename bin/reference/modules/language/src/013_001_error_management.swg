#global private

/**
# Error Management
Swag models errors as values. A function marked with 'fail' can either return
its normal result or exit early with 'fail errorValue'. The caller then chooses
whether to propagate, catch, dismiss, or expect success.
*/

struct MyError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

func count(name: string?)->u64 fail
{
    if name == null do
        fail MyError{base: Swag.BaseError{"name cannot be null"}, code: 7}
    return name.count
}

/**
# Catching Errors
'catch' handles the error locally and returns the default value for the result
type. To inspect the error, capture it with 'as err': this binds a fresh local
(of type `any?`) that is null on success and holds the caught error on
failure. The capture is visible in the enclosing scope, after the catch, so each
capture in a given scope needs its own name.

The captured payload stays alive until that scope ends, including across later
failures. Copies of the 'any' view and pointers derived from it borrow that lifetime
and cannot escape it. Use 'fail err' to propagate the captured error to a caller.
To retain an error after its capture ends, give it an explicit [[Swag.Error]] owner.
*/
#test
{
    let value = catch count(null) as err
    Swag.assert(value == 0)
    Swag.assert(err != null)

    let e = assume cast(MyError, err)
    Swag.assert(e.code == 7)
    Swag.assert(e.message == "name cannot be null")
}

/**
# Retaining Errors
[[Swag.Error.capture]] copies a live caught payload and retains its runtime message
storage. The owner may then outlive the catch scope, including a worker thread.
Other borrowed fields in the payload still need their original owners, and the
backing allocator must remain alive until every error owner and raised capture ends.

'try saved.raise()' propagates the retained error with its original dynamic type.
To inspect it, catch that call. The new capture owns its own lifetime, so resetting
'saved' does not invalidate it. An empty owner raises no error. Copying an owner
shares its retained payload; access to the same owner across threads needs
synchronization.
*/
#test
{
    var saved: Swag.Error
    {
        discard catch count(null) as err
        saved.capture(err)
    }

    catch saved.raise() as err
    saved.reset()
    Swag.assert(saved.isEmpty())
    Swag.assert(err is MyError)
    let e = assume cast(MyError, err)
    Swag.assert(e.code == 7)
    Swag.assert(e.message == "name cannot be null")
}

/**
# Handling on Failure with 'catch ... else'
'catch e else { H }' runs the anonymous handler 'H' only when 'e' fails. 'H'
cannot inspect the error (capture it with 'as err' for that); it is evaluated
lazily — only on the failure path — and may divert control flow (e.g. an early
'return'). To read the caught error, use the 'as err' capture form instead.
*/
func recordTrace(name: string?, out: *s32) fail
{
    out[] = cast(s32, (try count(name)))
}

#test
{
    var seen: s32 = -1

    catch recordTrace("swag", &seen) else do
        seen = -2
    Swag.assert(seen == 4)     // success: the handler does not run

    catch recordTrace(null, &seen) else
    {
        seen = -2
    }

    Swag.assert(seen == -2)     // failure: the handler ran instead
}

/**
# Dismissing Errors
To dismiss a failure and continue with the type default, use 'catch' without a
capture: the error is handled and dropped, and the expression yields the default
value for the result type. To keep the error, add an 'as err' capture; to use a
custom fallback, capture and branch ('var x = catch f() as err; if err != null do x = V').
*/
func safeCount(name: string?)->u64
{
    return catch count(name)
}

#test
{
    Swag.assert(safeCount("hello") == 5)
    Swag.assert(safeCount(null) == 0)
}

/**
# Propagating Errors
'try' propagates the current error to the caller, so it belongs inside a
function that can itself return an error.
*/
func propagateCount(name: string?)->u64 fail
{
    return try count(name)
}

#test
{
    let value = catch propagateCount("abc") as err
    Swag.assert(value == 3)
    Swag.assert(err == null)
}

#test
{
    let value = catch propagateCount(null) as err
    Swag.assert(value == 0)
    Swag.assert(err != null)
    Swag.assert(assume cast(MyError, err).code == 7)
}

/**
# Explicit Error Handling
Every call to a function declared with 'fail' needs 'try', 'catch', 'expect', or 'assume'.
Declaring the caller with 'fail' permits propagation, but does not make it implicit:
that takes '#[Swag.Propagate]', described below.
The compiler rejects a call that omits its error-management keyword.
*/
func explicitTryCount(name: string?)->u64 fail
{
    return try count(name)
}

#test
{
    let value = catch explicitTryCount(null) as err
    Swag.assert(value == 0)
    Swag.assert(err != null)
    Swag.assert(assume cast(MyError, err).code == 7)
}

/**
# Error-Handling Blocks
'try', 'catch' (optionally with 'as err' or 'else'), 'expect', and 'assume' can also guard
a whole block of code. Each fallible call inside the block still needs its own
keyword: use 'try' to pass its error to the enclosing block's handler.
*/
func blockTry(name0: string?, name1: string?)->u64 fail
{
    var total: u64 = 0
    try
    {
        total += try count(name0)
        total += try count(name1)
    }

    return total
}

func blockCatchCode()->s32
{
    catch
    {
        discard try count("ok")
        discard try count(null)
    } as err

    if err == null do
        return -1

    return assume cast(MyError, err).code
}

func blockCatchElse(name: string?)->u64
{
    catch
    {
        return try count(name)
    }
    else {}

    return 99
}

#test
{
    let value = catch blockTry("ab", null) as err
    Swag.assert(value == 0)
    Swag.assert(err != null)
    Swag.assert(assume cast(MyError, err).code == 7)
}

#test
{
    Swag.assert(blockCatchCode() == 7)
    Swag.assert(blockCatchElse("abcd") == 4)
    Swag.assert(blockCatchElse(null) == 99)
}

/**
# Implicit Propagation
When nearly every call of a function propagates, a 'try' on each one tells the reader
nothing. '#[Swag.Propagate]' reads every unmarked fallible call of the function body
as 'try', so the only error keywords left are those that handle a failure differently:
'catch', 'expect', and 'assume'.

The function must be declared with 'fail'. An unmarked failure goes exactly where 'try'
would send it: out of the function, or to an enclosing error-handling block. A written
'try' changes nothing and is reported as a warning. The attribute is an implementation
choice, not part of the signature: callers handle the function's errors as usual.

It governs only the body it is written on. A function or a lambda declared inside that
body spells its own handling, and a macro or a mixin cannot carry it, because its body
belongs to the caller. An attribute block applies it to each function it holds; '#global'
cannot apply it to a whole file. Editors that use the Swag language server show the
implicit 'try' as a hint before each call it applies to.

Use it for linear code where every step can fail and every failure ends the work:
setup code, scripts, test scenarios. Code that builds state by hand and must undo it on
failure reads better with each exit point spelled out.
*/
#[Swag.Propagate]
func implicitTotal(name0: string?, name1: string?)->u64 fail
{
    let first  = count(name0)
    let second = catch count(name1)
    return first + second + count("ok")
}

#test
{
    let both = try implicitTotal("ab", "cde")
    Swag.assert(both == 7)
    let caught = try implicitTotal("ab", null)
    Swag.assert(caught == 4)

    let value = catch implicitTotal(null, "cde") as err
    Swag.assert(value == 0)
    Swag.assert(assume cast(MyError, err).code == 7)
}

/**
# Expect
'expect' returns the successful result or panics. This contract holds in every
build configuration, including release and code with safety guards disabled.
A panic hook may report the error or transfer control, but returning from the
hook terminates the process. Use 'expect' for an invariant, not for an ordinary
failure that the caller should recover from.

A failed function produces no result. 'try' propagates its error without
constructing a replacement, and 'expect' stops without one. Both accept result
types with no default, including non-null pointers. A successful nullable result
remains nullable: 'expect' checks success, not presence.

'catch' resumes with a default result and therefore needs a result type with a
safe default. A non-null pointer has none; propagate it with 'try' or require
success with 'expect'.

Inside '#test', 'try' is equivalent to 'expect', so both forms keep the
success path concise when failure is not expected. An inlined function keeps
its own error propagation: 'try' in its body still passes failures to the
caller's handler.
*/
#test
{
    let value = try count("swag")
    Swag.assert(value == 4)
}

var requiredValue: s32 = 42

func loadRequiredValue()->*s32 fail => &requiredValue

#test
{
    let value = expect loadRequiredValue()
    #assert(#typeof(value) == *s32)
    Swag.assert(value[] == 42)
}

#test
{
    let value = expect count("swag")
    Swag.assert(value == 4)
}

/**
# Assume
'assume expression' states that every propagated failure in the expression is
impossible under the caller's invariants. With '.Assume' safety enabled, a failure
panics and reports the original error. Without that safety, the caller performs no
error-state test and establishes no error-handling frame for the assumption.

Failure then violates the program's contract: there is no guaranteed continuation,
replacement value, or recoverable error. Use 'expect' when failure must terminate
reliably in every configuration. A failed function still produces no result;
'assume' does not make it initialize a default.

Like 'expect', 'assume' preserves the successful result's type, including non-null
pointers and types without a default. It does not unwrap a nullable success value.
Nested 'catch' expressions keep handling their own failures normally.

For conversions, 'assume cast(T, value)' states the same invariant. Its checks use
'.Assume' for both type compatibility and presence. The same flag governs every
'assume', including casts inside a fallible expression.
*/
#test
{
    let value = assume count("swag")
    Swag.assert(value == 4)
    let required = assume loadRequiredValue()
    Swag.assert(required[] == 42)
}

/**
# Defer on Error Paths
A plain 'defer' still runs when a function exits through 'fail', because
'fail' is an early return carrying an error value.
*/
var DeferTrace: s32 = 0

func deferOnFail(name: string?)->u64 fail
{
    defer DeferTrace += 1
    return try count(name)
}

#test
{
    DeferTrace = 0
    let value = catch deferOnFail(null) as err
    Swag.assert(value == 0)
    Swag.assert(err != null)
    Swag.assert(DeferTrace == 1)
}
