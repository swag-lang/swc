#global private

using Swag

var returningExpectCalls:     u32
var returningExpectHookValid: bool

func copyExpectText(text: string)->string
{
    let context   = Swag.getContext()
    let allocator = Swag.makeInterface(&context.errorAllocator, ScratchAllocator, IAllocator)
    var request: AllocatorRequest
    request.size = text.count
    allocator.alloc(&request)
    Swag.memcpy(request.address, text.buffer, text.count)
    return Swag.makeString(cast([*] u8) request.address!, text.count)
}

func failExpectText(text: string) fail
{
    fail BaseError{copyExpectText(text)}
}

func returningExpectPanic(message: string?, _location: SourceCodeLocation)
{
    returningExpectCalls += 1
    let context = Swag.getContext()
    let depth   = context.errorIndex
    let trace   = context.traceIndex
    returningExpectHookValid = returningExpectHookValid and message != null and context.hasError == 0 and context.curError == null
    {
        catch failExpectText("a nested caught failure inside the returning panic hook") as nested
        if nested is BaseError as error do
            returningExpectHookValid = returningExpectHookValid and error.message == "a nested caught failure inside the returning panic hook"
        else do
            returningExpectHookValid = false
    }
    returningExpectHookValid = returningExpectHookValid and context.errorIndex == depth and context.traceIndex == trace and context.hasError == 0 and context.curError == null
}

func retainedExpectText(owner: const *Error, expected: string)->bool
{
    catch owner.raise() as captured
    if captured is BaseError as error do
        return error.message == expected
    return false
}

// A returning panic hook dismisses failed expect storage, including its nested caught errors.
#[Swag.Safety(.Expect, true)]
#test
{
    var allocator: Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    defer allocator.release()
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Context
    context.allocator        = Swag.makeInterface(&allocator, #typeof(allocator), IAllocator)
    context.defaultAllocator = context.allocator
    context.runtimeFlags     = previous.runtimeFlags
    context.errorAllocator.setCapacity(32, context.allocator)
    context.panic = &returningExpectPanic
    Swag.setContext(context)
    defer context.releaseErrorStorage()

    returningExpectCalls     = 0
    returningExpectHookValid = true
    let baseline = allocator.stats().countAlloc
    for 32 do
        expect failExpectText("a failed expect message larger than the configured error buffer")
    let after32 = allocator.stats().countAlloc
    for 32 do
        expect failExpectText("a failed expect message larger than the configured error buffer")
    let after64 = allocator.stats().countAlloc
    context.panic = previous.panic

    Swag.assert(returningExpectCalls == 64 and returningExpectHookValid)
    Swag.assert(context.errorIndex == 0 and context.hasError == 0 and context.curError == null and context.errorCaptures == null)
    Swag.assert(after32 == baseline and after64 == baseline, "returning expect hooks must reclaim each failed message frame")
}

// Retiring expect's failed frame preserves parent storage, an enclosing handler, and owner copies.
#[Swag.Safety(.Expect, true)]
#test
{
    var allocator: Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    defer allocator.release()
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Context
    context.allocator        = Swag.makeInterface(&allocator, #typeof(allocator), IAllocator)
    context.defaultAllocator = context.allocator
    context.runtimeFlags     = previous.runtimeFlags
    context.errorAllocator.setCapacity(16, context.allocator)
    context.panic = &returningExpectPanic
    Swag.setContext(context)
    defer context.releaseErrorStorage()

    returningExpectCalls     = 0
    returningExpectHookValid = true
    let baseline = allocator.stats().countAlloc
    let pending  = copyExpectText("pending parent text")
    var original: Error
    {
        catch failExpectText("a retained owner survives failed expect") as captured
        original.capture(captured)
    }
    var copied = original
    original.reset()
    let beforeHandler    = allocator.stats().countAlloc
    var parentValid      = false
    var handlerReclaimed = false
    catch failExpectText("the enclosing handler stays active") else
    {
        let depth        = context.errorIndex
        let trace        = context.traceIndex
        let hasError     = context.hasError
        let capture      = context.errorCaptures
        let beforeExpect = allocator.stats().countAlloc
        expect failExpectText("an expect failure inside the enclosing handler")
        handlerReclaimed = allocator.stats().countAlloc == beforeExpect
        parentValid      = context.errorIndex == depth and context.traceIndex == trace and context.hasError == hasError and context.errorCaptures == capture
        if context.curError is BaseError as error do
            parentValid = parentValid and error.message == "the enclosing handler stays active"
        else do
            parentValid = false
    }
    let afterHandler = allocator.stats().countAlloc
    let ownerValid   = retainedExpectText(&copied, "a retained owner survives failed expect")
    let pendingValid = pending == "pending parent text"
    copied.reset()
    context.releaseErrorStorage()
    let afterRelease = allocator.stats().countAlloc
    context.panic = previous.panic

    Swag.assert(returningExpectCalls == 1 and returningExpectHookValid)
    Swag.assert(parentValid and handlerReclaimed and afterHandler == beforeHandler)
    Swag.assert(ownerValid and pendingValid)
    Swag.assert(context.errorIndex == 0 and context.hasError == 0 and context.curError == null and context.errorCaptures == null)
    Swag.assert(afterRelease == baseline)
}
