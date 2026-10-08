#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// An error family two levels deep: the base state still sits at offset zero.
struct DeepError
{
    using base: Errors.BadParameterError     // Embedded base state.
}

func failWithMessage() fail
{
    fail Errors.BadParameterError{"the message text"}
}

func failWithoutMessage() fail
{
    fail Errors.BadParameterError{}
}

func failWithoutBase() fail
{
    fail Errors.InvalidVersion{wantedVersion: 1, foundVersion: 2}
}

func failDeep() fail
{
    fail DeepError{{"the deep text"}}
}

#test
{
    catch failWithMessage() as err
    Swag.assert(err != null)
    Swag.assert(Errors.message(err) == "the message text")
}

#test
{
    catch failWithoutMessage() as err
    Swag.assert(Errors.message(err) == "BadParameterError")
}

#test
{
    catch failWithoutBase() as err
    Swag.assert(Errors.message(err) == "InvalidVersion")
}

#test
{
    catch failDeep() as err
    Swag.assert(Errors.message(err) == "the deep text")
}

#test
{
    Swag.assert(Errors.message(null) == "")
}

#test
{
    // Native callbacks can build an error message before their first 'fail' initializes storage.
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Swag.Context
    context.allocator        = previous.allocator
    context.defaultAllocator = previous.defaultAllocator
    context.runtimeFlags     = previous.runtimeFlags
    Swag.setContext(context)
    defer context.errorAllocator.release()

    Swag.assert(Errors.mkString(null) == null)
    Swag.assert(Errors.mkString("") == "")
    var text       = String.from("a name collision")
    let persistent = Errors.mkString(text.toString())
    text.clear()
    Swag.assert(persistent == "a name collision")

    catch failWithMessage() as err
    Swag.assert(Errors.message(err) == "the message text")
}

// Message copies that are never raised still belong to the context and are reclaimed there.
#test
{
    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    defer allocator.release()

    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Swag.Context
    context.allocator        = Swag.makeInterface(&allocator, #typeof(allocator), Swag.IAllocator)
    context.defaultAllocator = context.allocator
    context.runtimeFlags     = previous.runtimeFlags
    context.errorAllocator.setCapacity(256, context.allocator)
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let baseline = allocator.stats().countAlloc
    var copied: string?
    for 32 do
        copied = Errors.mkString("dynamic error message")
    let valid = copied == "dynamic error message"
    context.errorAllocator.release()
    let afterRelease = allocator.stats().countAlloc
    Swag.setContext(previous)

    Swag.assert(valid)
    Swag.assert(afterRelease == baseline)
}

func failCopiedMessage(text: string) fail
{
    fail Errors.BadParameterError{Errors.mkString(text)}
}

// A copied message is not consumed by an unrelated failure. A rethrow then retains it even
// when the context releases the buffer while the outer capture is still alive.
#test
{
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Swag.Context
    context.allocator        = previous.allocator
    context.defaultAllocator = previous.defaultAllocator
    context.runtimeFlags     = previous.runtimeFlags
    context.errorAllocator.setCapacity(16, context.allocator!)
    defer context.errorAllocator.release()
    Swag.setContext(context)

    let pending = Errors.mkString("a pending message survives an unrelated handled failure")
    catch failWithoutBase()
    Swag.assert(pending == "a pending message survives an unrelated handled failure")

    catch
    {
        catch failCopiedMessage("a copied message survives rethrow and allocator release") as inner
        fail inner
    } as outer
    context.errorAllocator.release()
    Swag.assert(Errors.message(outer) == "a copied message survives rethrow and allocator release")
}

// The producer's handled frame has released its message arena before parallel publication.
// Its capture and the transport copy both leave before this caller examines the final error.
#test
{
    catch parallel for || 257
    {
        try failCopiedMessage("the parallel error retains its producer's copied text")
    } as error
    Swag.assert(Errors.message(error) == "the parallel error retains its producer's copied text")
}

var copiedThreadMessagesValid: Swag.AtomicFlag

func consumeThreadMessages(_: Threading.Thread)
{
    let pending = Errors.mkString("an unraised thread message is reclaimed on exit")
    var valid   = true
    for 32
    {
        catch failCopiedMessage("a handled thread message") as error
        valid = valid and Errors.message(error) == "a handled thread message"
    }

    if valid and pending == "an unraised thread message is reclaimed on exit" do
        discard copiedThreadMessagesValid.raise()
}

// A real thread exits with an unraised copied view after handling its own errors. Its public
// lifecycle releases that root storage, while its allocator interface still belongs to us.
#test
{
    if Swag.jit() do
        return
    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    defer allocator.release()
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Swag.Context
    context.allocator        = Swag.makeInterface(&allocator, #typeof(allocator), Swag.IAllocator)
    context.defaultAllocator = context.allocator
    context.runtimeFlags     = previous.runtimeFlags
    Swag.setContext(context)
    defer context.errorAllocator.release()

    let baseline = allocator.stats().countAlloc
    copiedThreadMessagesValid.reset()
    {
        var thread: Threading.Thread
        expect thread.init(&consumeThreadMessages)
        expect thread.start()
        thread.wait()
    }

    let afterThread = allocator.stats().countAlloc
    Swag.setContext(previous)
    Swag.assert(copiedThreadMessagesValid.isRaised())
    Swag.assert(afterThread == baseline)
}

struct OwnedThreadError
{
    error: Swag.Error
}

func publishOwnedThreadError(thread: Threading.Thread)
{
    let state = cast(*OwnedThreadError, thread.userParam!)

    // The text is allocated in the producer's root storage, before its catch frame begins.
    let message = Errors.mkString("the public error owner retains text beyond producer exit")
    catch
    {
        fail Errors.BadParameterError{message}
    } as error
    state.error.capture(error)
}

// Public ownership crosses an actual joined thread and preserves arbitrary dynamic types.
// Resetting each transport copy leaves the final lexical capture alive until its own exit.
#test
{
    if Swag.jit() do
        return
    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    defer allocator.release()
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Swag.Context
    context.allocator        = Swag.makeInterface(&allocator, #typeof(allocator), Swag.IAllocator)
    context.defaultAllocator = context.allocator
    context.runtimeFlags     = previous.runtimeFlags
    Swag.setContext(context)
    defer context.releaseErrorStorage()

    let baseline = allocator.stats().countAlloc
    var state: OwnedThreadError
    {
        var thread: Threading.Thread
        expect thread.init(&publishOwnedThreadError, &state)
        expect thread.start()
        thread.wait()
    }

    var copied = state.error
    state.error.reset()
    var valid: bool
    {
        catch copied.raise() as error
        copied.reset()
        valid = (error is Errors.BadParameterError) and Errors.message(error) == "the public error owner retains text beyond producer exit"
    }

    let afterOwner = allocator.stats().countAlloc
    Swag.assert(valid)
    Swag.assert(afterOwner == baseline)
}
