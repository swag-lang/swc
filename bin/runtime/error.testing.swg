#global if #command == Swag.CompilerCommand.Test
#global namespace Swag

// This test seam keeps private record transport inside the bootstrap. Its caller receives
// only the outcome, never a raw record or a shutdown operation on the process worker pool.
private struct ErrorTransportTestState
{
    context:        Context
    owned:          *ErrorRecord?
    drops:          [16] AtomicValue'u32
    generation:     u32
    producerThread: u64
    released:       bool
}

private struct ErrorTransportTestPayload
{
    using base: BaseError
    drops:      [*] AtomicValue'u32
    generation: u32
}

impl ErrorTransportTestPayload
{
    mtd opPostCopy() { .generation += 1 }
    mtd opDrop() { .drops[.generation].add(1) }
}

private func copyTransportTestMessage(text: string)->string
{
    let context   = Swag.getContext()
    let allocator = Swag.makeInterface(&context.errorAllocator, ScratchAllocator, IAllocator)
    var request: AllocatorRequest
    request.size = text.count
    allocator.alloc(&request)
    Swag.memcpy(request.address, text.buffer, text.count)
    return Swag.makeString(cast([*] u8) request.address!, text.count)
}

private func failTransportTestMessage(message: string, drops: [*] AtomicValue'u32) fail
{
    fail ErrorTransportTestPayload{base: BaseError{message}, drops: drops}
}

#[Swag.CallingConvention(.C)]
private func errorTransportTestThread(param: *void?)->u32
{
    let state = cast(*ErrorTransportTestState) param!
    Swag.setContext(state.context)
    state.producerThread = __hostCurrentThreadId()
    {
        // Allocate outside the catch frame, so the producer's root allocator still owns a
        // lease until thread teardown. The published record must retain that same arena.
        let message = copyTransportTestMessage("the joined producer's pending copied message")
        catch failTransportTestMessage(message, state.drops.buffer) as error
        if error is ErrorTransportTestPayload as value
        {
            state.generation = value.generation
            state.owned      = __copyErrRecord(error!)
        }
    }

    state.context.releaseErrorStorage()
    releaseAllocatorThreadCache()
    state.released = true
    return 0
}

private func raiseTransportTestRecord(record: *ErrorRecord) fail
{
    __setOwnedErrRecord(record)
}

#[Swag.NoDoc]
public func testErrorTransportAfterThreadExit()->bool
{
    if Swag.jit() do
        return true
    var allocator: Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    defer allocator.release()
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    let allocatorInterface = Swag.makeInterface(&allocator, #typeof(allocator), IAllocator)
    var context: Context
    context.allocator        = allocatorInterface
    context.defaultAllocator = allocatorInterface
    context.runtimeFlags     = previous.runtimeFlags
    context.errorAllocator.setCapacity(16, allocatorInterface)
    Swag.setContext(context)
    defer context.releaseErrorStorage()

    var state: ErrorTransportTestState
    state.context.allocator        = allocatorInterface
    state.context.defaultAllocator = allocatorInterface
    state.context.runtimeFlags     = previous.runtimeFlags
    state.context.errorAllocator.setCapacity(16, allocatorInterface)
    defer __releaseErrRecord(state.owned)
    let baseline     = allocator.stats().countAlloc
    let callerThread = __hostCurrentThreadId()
    let thread       = __hostThreadCreate(&errorTransportTestThread, &state)
    if not thread do
        return false
    __hostThreadJoin(thread)

    var valid = state.released and state.producerThread != callerThread and state.owned != null
    if not valid do
        return false
    let generation = state.generation
    valid = valid and state.drops[generation].load() == 1
    {
        catch raiseTransportTestRecord(state.owned!) as error
        __releaseErrRecord(state.owned)
        state.owned = null
        if error is ErrorTransportTestPayload as value do
            valid = valid and value.message == "the joined producer's pending copied message" and value.generation == generation + 2
        else do
            valid = false
        valid = valid and state.drops[generation + 1].load() == 1 and state.drops[generation + 2].load() == 0
    }

    return valid and state.drops[generation + 2].load() == 1 and allocator.stats().countAlloc == baseline
}
