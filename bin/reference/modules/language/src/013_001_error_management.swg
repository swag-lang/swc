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
'catch' handles an error locally. It reads in three ways:

- 'catch e' resumes with the default value of the result type when 'e' fails.
- 'catch e orelse V' resumes with 'V' instead.
- 'catch e { H }' runs the handler 'H' only when 'e' fails.

The operand binds like the operand of a unary operator: 'catch f() == 0' compares
the caught result. The 'orelse' value takes the rest of the expression, as it does
for any 'orelse'.

Inside the handler or the 'orelse' value, 'Swag.err' is the error: a borrowed 'any',
non-null because the handler runs only on failure. In a nested 'catch', it names the
innermost error. Outside a handler, 'Swag.err' does not exist.

A block handler used in a value expression must leave the surrounding flow with
'return', 'fail', 'break', or 'continue'.

Copies of the error view and pointers derived from it borrow the handler's
lifetime and cannot escape it. Use 'fail Swag.err' to propagate the caught error.
To retain it after the handler ends, give it an explicit [[Swag.Error]] owner.
*/
#test
{
    let value = catch count(null) orelse assume cast(MyError, Swag.err).code
    Swag.assert(value == 7)
    let other = catch count(null) orelse assume cast(MyError, Swag.err).code + 1
    Swag.assert(other == 8)
}

/**
# Retaining Errors
[[Swag.Error.capture]] copies a live caught payload and retains its runtime message
storage. The owner may then outlive the handler, including a worker thread.
Other borrowed fields still need their original owners, and the backing allocator
must remain alive until every error owner and raised capture ends.

To store the outcome directly, declare the owner and write 'as saved'. The owner
is evaluated once before the operand. Failure retains the handled payload without
copying it; success resets the owner to empty. This form needs no handler: a result
that is read still resumes with the default value of its type, or with 'orelse V'.

[[Swag.Error.value]] borrows the retained error for later inspection; an empty
owner returns null. Resetting, replacing, or dropping the owner invalidates that
view. 'try saved.raise()' propagates the retained error with its dynamic type.
Copying an owner shares its retained payload. Access to the same owner across
threads needs synchronization.
*/
#test
{
    var saved: Swag.Error
    discard catch count(null) as saved
    let err = saved.value()
    Swag.assert(err is MyError)
    Swag.assert(assume cast(MyError, err).code == 7)

    catch saved.raise()
    {
        saved.reset()
        Swag.assert(saved.isEmpty())
        Swag.assert(assume cast(MyError, Swag.err).message == "name cannot be null")
    }
}

#test
{
    var saved: Swag.Error
    let value = catch count(null) as saved orelse 17
    Swag.assert(value == 17 and not saved.isEmpty())
    let other = catch count("ready") as saved
    Swag.assert(other == 5 and saved.isEmpty())
}

/**
# Handling on Failure
'catch e { H }' runs the handler 'H' only when 'e' fails; 'catch e do S' runs a
single statement. 'Swag.err' reads the error inside 'H'.
A handler on a statement may finish normally. A handler on a value expression must
leave the surrounding flow.

The block that follows a 'catch' operand is always its handler. To pass trailing
code to a macro under 'catch', write it as an explicit '#code' literal. In the
header of 'if', 'while', 'for', 'switch' or 'with', the '{' that follows a 'catch'
operand opens the statement body: give the handler parentheses there.
*/
func recordTrace(name: string?, out: *s32) fail
{
    out[] = cast(s32, (try count(name)))
}

#test
{
    var seen: s32 = -1

    catch recordTrace("swag", &seen) do
        seen = -2
    Swag.assert(seen == 4)     // success: the handler does not run

    catch recordTrace(null, &seen)
    {
        seen = -2
    }

    Swag.assert(seen == -2)     // failure: the handler ran instead
}

/**
# Replacing a Failed Result
'catch e' yields the default value of the result type when 'e' fails: the value
'var x: T' would hold, with struct field initializers applied, null for a nullable
type, and zero for a number. A type that has no default value, such as a non-null
pointer, needs the replacement to be written.

'catch e orelse V' yields 'V' instead. 'V' converts to the result type of 'e' and is
evaluated only when it is needed, so it can read 'Swag.err'. Because the replacement
is written, the result type needs no default: a non-null pointer can be caught too.

Like any 'orelse', 'V' replaces a missing value: with a nullable result, a success
that returns null takes 'V' as well, and the expression then holds a value whenever
'V' does. There is no error in that case, so 'V' cannot read 'Swag.err' there.

When the result is not needed, write 'discard catch': success drops its result and
failure drops its error.
*/
func safeCount(name: string?)->u64
{
    return catch count(name)
}

func countOrCode(name: string?)->u64
{
    return catch count(name) orelse cast(u64, assume cast(MyError, Swag.err).code)
}

#test
{
    Swag.assert(safeCount("hello") == 5)
    Swag.assert(safeCount(null) == 0)
    Swag.assert(countOrCode(null) == 7)

    let required = catch loadRequiredValue() orelse &requiredValue
    Swag.assert(required[] == 42)

    discard catch count(null)
}

struct Settings
{
    width: s32    = 640
    title: string = "untitled"
}

func loadSettings(fileName: string?)->Settings fail
{
    if fileName == null do
        fail MyError{base: Swag.BaseError{"no settings file"}}
    return Settings{width: 1024, title: fileName}
}

func findName(id: s32)->string? fail
{
    if id == 0 do
        fail MyError{base: Swag.BaseError{"unknown id"}}
    return "first"
}

#test
{
    // The default of a struct is the one its field initializers give.
    let settings = catch loadSettings(null)
    Swag.assert(settings.width == 640 and settings.title == "untitled")

    // A nullable result defaults to null.
    let name = catch findName(0)
    Swag.assert(name == null)

    // 'orelse' replaces a failure, and a successful null alike.
    let named = catch findName(0) orelse "anonymous"
    Swag.assert(named == "anonymous")
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
    var errOutcome: Swag.Error
    let value = catch propagateCount("abc") as errOutcome
    let err   = errOutcome.value()
    Swag.assert(value == 3)
    Swag.assert(err == null)
}

#test
{
    var errOutcome: Swag.Error
    let value = catch propagateCount(null) as errOutcome
    let err   = errOutcome.value()
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
    var errOutcome: Swag.Error
    let value = catch explicitTryCount(null) as errOutcome
    let err   = errOutcome.value()
    Swag.assert(value == 0)
    Swag.assert(err != null)
    Swag.assert(assume cast(MyError, err).code == 7)
}

/**
# Error-Handling Blocks
'try', 'catch' (optionally with 'as owner' or a handler), 'expect', and 'assume' can also guard
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
    var errOutcome: Swag.Error
    catch {
        discard try count("ok")
        discard try count(null)
    } as errOutcome

    let err = errOutcome.value()

    if err == null do
        return -1

    return assume cast(MyError, err).code
}

func blockCatchDismiss(name: string?)->u64
{
    catch
    {
        return try count(name)
    }

    return 99
}

#test
{
    var errOutcome: Swag.Error
    let value = catch blockTry("ab", null) as errOutcome
    let err   = errOutcome.value()
    Swag.assert(value == 0)
    Swag.assert(err != null)
    Swag.assert(assume cast(MyError, err).code == 7)
}

#test
{
    Swag.assert(blockCatchCode() == 7)
    Swag.assert(blockCatchDismiss("abcd") == 4)
    Swag.assert(blockCatchDismiss(null) == 99)
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
    let both = expect implicitTotal("ab", "cde")
    Swag.assert(both == 7)
    let caught = expect implicitTotal("ab", null)
    Swag.assert(caught == 4)

    var errOutcome: Swag.Error
    let value = catch implicitTotal(null, "cde") as errOutcome
    let err   = errOutcome.value()
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

A 'catch' expression resumes with the default value of its type, names its
replacement with 'orelse', or uses a block handler that leaves the surrounding
flow. With 'orelse' or such a handler, it accepts non-null results.

Inside '#test', write 'expect' when an error must stop the test. 'try' follows
the ordinary propagation rule and needs an enclosing error-handling block.
An inlined function keeps its own error propagation: 'try' in its body still
passes failures to the caller's handler.
*/
#test
{
    let value = expect count("swag")
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
pointers and types without a default. It does not unwrap a nullable success value;
write `unwrap assume operation()` when presence is also an invariant.
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
    var errOutcome: Swag.Error
    let value = catch deferOnFail(null) as errOutcome
    let err   = errOutcome.value()
    Swag.assert(value == 0)
    Swag.assert(err != null)
    Swag.assert(DeferTrace == 1)
}
