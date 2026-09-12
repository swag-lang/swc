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
*/
#test
{
    let value = catch count(null) as err
    Swag.assert(value == 0)
    Swag.assert(err != null)

    let e = cast(MyError) err
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
    out[] = cast(s32) (try count(name))
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
    Swag.assert((cast(MyError) err).code == 7)
}

/**
# Explicit Error Handling
Every call to a function declared with 'fail' needs 'try', 'catch', or 'expect'.
Declaring the caller with 'fail' permits propagation, but does not make it implicit.
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
    Swag.assert((cast(MyError) err).code == 7)
}

/**
# Error-Handling Blocks
'try', 'catch' (optionally with 'as err' or 'else'), and 'expect' can also guard
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

    return (cast(MyError) err).code
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
    Swag.assert((cast(MyError) err).code == 7)
}

#test
{
    Swag.assert(blockCatchCode() == 7)
    Swag.assert(blockCatchElse("abcd") == 4)
    Swag.assert(blockCatchElse(null) == 99)
}

/**
# Expect
'expect' asserts that a fallible operation succeeds. An unexpected failure
panics while the '.Expect' safety guard is enabled; when that guard is disabled,
the result uses its type's default. Use it for an invariant, not for an ordinary
failure that the caller should recover from.

Forms that need a default result, including 'catch' and 'expect', require a
result type with a safe default. A non-null pointer has none; propagate such a
result with 'try', or design the failure-handling boundary to return a type
that can represent absence.

Inside '#test', 'try' is equivalent to 'expect', so both forms keep the
success path concise when failure is not expected.
*/
#test
{
    let value = try count("swag")
    Swag.assert(value == 4)
}

#test
{
    let value = expect count("swag")
    Swag.assert(value == 4)
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
