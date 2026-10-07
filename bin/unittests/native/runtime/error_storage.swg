#global private

using Swag

func failStoredScalar() fail
{
    fail 7's64
}

func copyStoredText(text: string)->string
{
    let context   = Swag.getContext()
    let allocator = Swag.makeInterface(&context.errorAllocator, ScratchAllocator, IAllocator)
    var request: AllocatorRequest
    request.size = text.count
    allocator.alloc(&request)
    Swag.memcpy(request.address, text.buffer, text.count)
    return Swag.makeString(cast([*] u8, request.address!), text.count)
}

func failStoredText(text: string) fail
{
    fail BaseError{copyStoredText(text)}
}

func returnStoredText(text: string)->string? fail
{
    return copyStoredText(text)
}

// Dismissing a scalar failure releases its payload, without waiting for context teardown.
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
    context.errorAllocator.setCapacity(256, context.allocator)
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let baseline = allocator.stats().countAlloc
    for 32 do
        catch failStoredScalar()
    let after32 = allocator.stats().countAlloc
    for 32 do
        catch failStoredScalar()
    let after64 = allocator.stats().countAlloc
    context.errorAllocator.release()
    let afterRelease = allocator.stats().countAlloc
    Swag.setContext(previous)

    Swag.assert(after32 == baseline)
    Swag.assert(after64 == baseline)
    Swag.assert(afterRelease == baseline)
}

// Releasing a context's bump buffer and spill blocks preserves both captured messages;
// their last lexical owners reclaim the detached storage.
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
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let baseline = allocator.stats().countAlloc
    var shortValid, longValid: bool
    {
        catch failStoredText("short") as shortError
        catch failStoredText("a long retained message stored beyond the small bump buffer") as longError
        context.errorAllocator.release()
        if shortError is BaseError as error do
            shortValid = error.message == "short"
        if longError is BaseError as error do
            longValid = error.message == "a long retained message stored beyond the small bump buffer"
    }
    let afterOwners = allocator.stats().countAlloc
    Swag.setContext(previous)

    Swag.assert(shortValid and longValid)
    Swag.assert(afterOwners == baseline)
}

// Each dismissed handled operation releases its message arena, without a manual release
// between failures. Small capacity exercises tracked spill blocks as well as the bump block.
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
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let baseline = allocator.stats().countAlloc
    for 32 do
        catch failStoredText("a copied failure message larger than the configured error buffer")
    let after32 = allocator.stats().countAlloc
    for 32 do
        catch failStoredText("a copied failure message larger than the configured error buffer")
    let after64 = allocator.stats().countAlloc
    Swag.setContext(previous)
    Swag.assert(after32 == baseline and after64 == baseline)
}

// Successful catch/expect operands can return copied plain views. An unrelated failure
// neither consumes those views nor a pending copy made before entering any operand.
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
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let baseline = allocator.stats().countAlloc
    let pending  = copyStoredText("pending parent text")
    let expected = expect returnStoredText("returned by successful expect")
    let caught   = catch returnStoredText("returned by successful catch")
    catch failStoredText("an unrelated handled message")
    let valid = pending == "pending parent text" and expected == "returned by successful expect" and
                caught == "returned by successful catch"
    context.errorAllocator.release()
    let afterRelease = allocator.stats().countAlloc
    Swag.setContext(previous)
    Swag.assert(valid)
    Swag.assert(afterRelease == baseline)
}

struct PairedStoredError
{
    using base: BaseError
    second:     string?
}

func failNestedStoredText() fail
{
    let first  = copyStoredText("before the successful child")
    let second = expect returnStoredText("returned from the successful child")
    fail PairedStoredError{base: BaseError{first}, second: second}
}

var storedTextCleanupCount: u32

func failStoredTextWithCleanup() fail
{
    defer #fail
    {
        discard copyStoredText("cleanup can also make an unraised message")
        catch failStoredText("cleanup dismisses this separate failure")
        storedTextCleanupCount += 1
    }
    try failStoredText("the original failure survives cleanup")
}

// Nested successful storage merges into the failing parent. Failure cleanup can allocate
// and dismiss errors without losing the original message or leaking any of the frame arenas.
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
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let baseline = allocator.stats().countAlloc
    var pairValid, cleanupValid: bool
    {
        catch failNestedStoredText() as paired
        if paired is PairedStoredError as error do
            pairValid = error.message == "before the successful child" and
                        error.second == "returned from the successful child"
    }
    let afterPair = allocator.stats().countAlloc
    storedTextCleanupCount = 0
    {
        catch failStoredTextWithCleanup() as original
        if original is BaseError as error do
            cleanupValid = error.message == "the original failure survives cleanup"
    }
    let afterCleanup = allocator.stats().countAlloc
    Swag.setContext(previous)
    Swag.assert(pairValid and cleanupValid)
    Swag.assert(storedTextCleanupCount == 1)
    Swag.assert(afterPair == baseline and afterCleanup == baseline)
}

// Many successful returns retain plain views until their surrounding context releases them.
// Teardown must not consume stack depth proportional to that success history.
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
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let baseline      = allocator.stats().countAlloc
    var last: string? = ""
    for 16384 do
        last = expect returnStoredText("a successful copied message")
    let valid = last == "a successful copied message"
    context.errorAllocator.release()
    let afterRelease = allocator.stats().countAlloc
    Swag.setContext(previous)
    Swag.assert(valid)
    Swag.assert(afterRelease == baseline)
}

// The parallel failure publication and receiver copies keep the message after the worker
// capture and transport owner have gone. The ordinary context can release independently.
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
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let baseline = allocator.stats().countAlloc
    var valid: bool
    {
        catch parallel for || 1
        {
            try failStoredText("the copied parallel error retains its message")
        } as transported
        context.errorAllocator.release()
        if transported is BaseError as error do
            valid = error.message == "the copied parallel error retains its message"
    }
    let afterOwner = allocator.stats().countAlloc
    Swag.setContext(previous)
    Swag.assert(valid)
    Swag.assert(afterOwner == baseline)
}

// The bootstrap-only seam publishes on a different OS thread, releases that producer's root
// message allocator, joins it, then re-raises and drops every generation on this thread.
#test
{
    if not Swag.jit() do
        Swag.assert(Swag.testErrorTransportAfterThreadExit())
}
