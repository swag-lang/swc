#global private

// In a '#[Swag.Propagate]' function every unmarked fallible call reads as 'try': its failure
// goes to the nearest handler, which is the function's own 'fail' exit or an enclosing
// error-handling block. Calls that spell 'catch', 'expect', or 'assume' keep their handling.

struct PropagateError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

func propagateCount(ok: bool, code = 1)->s32 fail
{
    if not ok do
        fail PropagateError{base: Swag.BaseError{"propagate"}, code: code}
    return 10
}

func propagateErrorCode(err: any?)->s32
{
    if err is PropagateError as error do
        return error.code
    return 0
}

#[Swag.Propagate]
func propagateSum(first, second: bool)->s32 fail
{
    let a = propagateCount(first, 1)
    let b = propagateCount(second, 2)
    return a + b
}

#test
{
    var errOutcome: Swag.Error
    var sum:        #decltype(expect propagateSum(true, true))
    catch { sum = try propagateSum(true, true) } as errOutcome
    let err = errOutcome.value()
    Swag.assert(sum == 20 and err == null)
    var secondOutcome: Swag.Error
    discard catch propagateSum(true, false) as secondOutcome
    let second = secondOutcome.value()
    Swag.assert(propagateErrorCode(second) == 2)
    var firstOutcome: Swag.Error
    discard catch propagateSum(false, true) as firstOutcome
    let first = firstOutcome.value()
    Swag.assert(propagateErrorCode(first) == 1)
}

// A spelled 'catch' handles its own failure; the unmarked call after it still propagates.
#[Swag.Propagate]
func propagateAfterCatch(ok: bool)->s32 fail
{
    var errOutcome: Swag.Error
    let recovered = catch propagateCount(false, 3) as errOutcome
    let err       = errOutcome.value()
    Swag.assert(recovered == 0 and propagateErrorCode(err) == 3)
    return propagateCount(ok, 4)
}

#test
{
    Swag.assert((catch propagateAfterCatch(true)) == 10)
    var errOutcome: Swag.Error
    discard catch propagateAfterCatch(false) as errOutcome
    let err = errOutcome.value()
    Swag.assert(propagateErrorCode(err) == 4)
}

// Inside a 'catch' block, an unmarked call goes to that block, exactly where 'try' sends it.
#[Swag.Propagate]
func propagateIntoBlock(ok: bool)->s32 fail
{
    var reached = 0
    catch
    {
        discard propagateCount(ok, 5)
        reached = 1
    } { return -propagateErrorCode(Swag.err) }
    return reached + propagateCount(true)
}

#test
{
    Swag.assert((catch propagateIntoBlock(true)) == 11)
    Swag.assert((catch propagateIntoBlock(false)) == -5)
}

struct PropagateReader
{
    fails: bool
}

impl PropagateReader
{
    #[Swag.Propagate]
    mtd read()->s32 fail => propagateCount(not .fails, 6)
}

// Methods, nested arguments, and dynamic casts are fallible expressions too.
#[Swag.Propagate]
func propagateNested(reader: *PropagateReader, boxed: any)->s32 fail
{
    let value = cast(s32, boxed)
    return propagateCount(reader.read() == 10, 7) + value
}

#test
{
    var reader: PropagateReader
    Swag.assert((catch propagateNested(&reader, 5's32)) == 15)

    var castErrorOutcome: Swag.Error
    discard catch propagateNested(&reader, "text") as castErrorOutcome
    let castError = castErrorOutcome.value()
    Swag.assert(castError != null and propagateErrorCode(castError) == 0)

    reader.fails = true
    var readErrorOutcome: Swag.Error
    discard catch propagateNested(&reader, 5's32) as readErrorOutcome
    let readError = readErrorOutcome.value()
    Swag.assert(propagateErrorCode(readError) == 6)
}

// Deferred cleanup runs on an implicit propagation as it does on 'try'.
#[Swag.Propagate]
func propagateDefer(ok: bool, log: *s32) fail
{
    defer #fail log[] += 100
    defer log[] += 1
    discard propagateCount(ok)
}

#test
{
    var log = 0
    discard catch propagateDefer(true, &log)
    Swag.assert(log == 1)
    discard catch propagateDefer(false, &log)
    Swag.assert(log == 102)
}

// An explicit inline expansion keeps the callee's propagation, whatever the caller spells.
#[Swag.Propagate, Swag.Inline]
func propagateInline(ok: bool)->s32 fail => propagateCount(ok, 8) + 1

#[Swag.Propagate]
func(T) propagateGeneric(value: T, ok: bool)->T fail
{
    discard propagateCount(ok, 9)
    return value
}

#test
{
    Swag.assert((catch propagateInline(true)) == 11)
    var inlineErrorOutcome: Swag.Error
    discard catch propagateInline(false) as inlineErrorOutcome
    let inlineError = inlineErrorOutcome.value()
    Swag.assert(propagateErrorCode(inlineError) == 8)

    Swag.assert((catch propagateGeneric(3's32, true)) == 3)
    var genericErrorOutcome: Swag.Error
    discard catch propagateGeneric(1.5'f32, false) as genericErrorOutcome
    let genericError = genericErrorOutcome.value()
    Swag.assert(propagateErrorCode(genericError) == 9)
}

// An attribute block broadcasts 'Swag.Propagate' to each function it holds.
#[Swag.Propagate]
{
    func propagateBlockFirst(ok: bool)->s32 fail  => propagateCount(ok, 10)
    func propagateBlockSecond(ok: bool)->s32 fail => propagateBlockFirst(ok) * 2
}

#test
{
    Swag.assert((catch propagateBlockSecond(true)) == 20)
    var errOutcome: Swag.Error
    discard catch propagateBlockSecond(false) as errOutcome
    let err = errOutcome.value()
    Swag.assert(propagateErrorCode(err) == 10)
}
