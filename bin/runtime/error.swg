using Swag

////////////////////////////////////////////////////////////

namespace Swag
{
    // Owns a captured error beyond its original catch scope.
    //
    // A default value is empty. Capture a caught value while its scope is still alive, then
    // use [[Swag.Error.raise]] to propagate or inspect the same dynamic error type later.
    // Copying an owner shares its retained payload; resetting one copy leaves the others valid.
    // Copied runtime message storage survives the originating context and thread.
    //
    // Capturing copies the payload using its ordinary copy behavior. Other borrowed fields
    // still require their original owners, and every backing allocator must outlive all error
    // owners and raised captures that use it. Synchronize publication and access to the same
    // owner across threads. Distinct copies can be used independently when the payload's copy
    // and destruction behavior and its allocators support those threads.
    //
    // ```swag
    // var saved: Swag.Error
    // {
    //     catch { fail 42's32 } as error
    //     saved.capture(error)
    // }
    // catch saved.raise() as error
    // Swag.assert(error is s32)
    // ```
    #[Opaque]
    public struct Error
    {
        private record: *ErrorRecord?
    }

    public impl Error
    {
        // Releases this owner's reference when it leaves scope.
        mtd opDrop()
        {
            __releaseErrRecord(.record)
        }

        // Shares the retained payload with the copied owner.
        mtd opPostCopy()
        {
            if .record do
                .record.references.add(1)
        }

        // Replaces the retained error with a copy of a live caught value.
        //
        // Call while `error` still belongs to its catch scope on the current thread.
        // Its dynamic payload and copied message storage are retained independently of that
        // scope. A null value resets this owner. The new copy is made before the old one drops.
        mtd capture(error: any?)
        {
            var record: *ErrorRecord?
            if error do
                record = __copyErrRecord(error)
            .reset()
            .record = record
        }

        // Releases this owner's reference and restores the empty state.
        //
        // Other owner copies and errors already raised from them remain valid.
        mtd reset()
        {
            Swag.drop(me, 1)
            Swag.init(me, 1)
        }

        // Reports whether this owner has no retained error.
        mtd const isEmpty()->bool => .record == null

        // Raises a copy of the retained error, or succeeds when this owner is empty.
        //
        // The raised value preserves its dynamic type and copied message storage. This owner
        // stays valid and can be raised again. To inspect it, catch this call and inspect that
        // lexical capture; the new capture survives a reset or drop of this owner.
        mtd const raise() fail
        {
            if .record do
                __setOwnedErrRecord(.record)
        }
    }

    // Runtime-only owners. An 'any' remains a borrowed view; the compiler gives each catch
    // capture a hidden lexical owner, and each handler a temporary owner for every exit path.
    #[NoDoc]
    struct ErrorMessageArena
    {
        references: AtomicValue'u64
        allocator:  IAllocator
        storage:    ScratchAllocator
        retained:   *ErrorMessageLink?
    }

    #[NoDoc]
    struct ErrorMessageLink
    {
        references:  AtomicValue'u64
        allocator:   IAllocator
        arena:       *ErrorMessageArena
        next:        *ErrorMessageLink?
        releaseNext: *ErrorMessageLink?     // Iterative destruction continuation after references reach zero.
    }

    #[NoDoc]
    struct ErrorRecord
    {
        references: AtomicValue'u64
        allocator:  IAllocator
        value:      any?
        messages:   *ErrorMessageLink?
    }

    #[NoDoc, NoCopy]
    struct ErrorCapture
    {
        record:        *ErrorRecord?
        context:       *Context?
        previous:      *ErrorCapture?
        next:          *ErrorCapture?
        previousError: any?
        handler:       bool
    }

    impl ErrorCapture
    {
        mtd opDrop()
        {
            let record  = .record
            let context = .context
            if context
            {
                if .previous do
                    .previous.next = .next
                else do
                    context.errorCaptures = .next
                if .next do
                    .next.previous = .previous

                if .handler
                {
                    if record and context.curError.buffer == record.value.buffer do
                        context.curError = .previousError

                    // Implicit drops run inside their own error-preservation frame. Do not
                    // let its later pop restore the just-dismissed handler's borrowed view.
                    for index in context.errorIndex
                    {
                        let saved = &context.errors[index].pushCurError
                        if record and saved[].buffer == record.value.buffer do
                            saved[] = .previousError
                    }
                }
            }

            Swag.init(me, 1)
            __releaseErrRecord(record)
        }
    }

    impl Context
    {
        // Releases error state and copied messages after this context's work has finished.
        //
        // Call on the current context after its callbacks and handled operations have returned,
        // before replacing or destroying it. No lexical catch capture may still use this context.
        // An error already transported elsewhere retains the message storage it owns.
        public mtd releaseErrorStorage()
        {
            Swag.assert(.errorIndex == 0 and .errorCaptures == null)
            __releaseErrContext(me)
        }
    }
}

private func __allocateErrMemory(allocator: IAllocator, size: u64)->*void
{
    var request: AllocatorRequest
    request.size = Swag.max(size, 1'u64)
    allocator.alloc(&request)
    if not request.address do
        Swag.panic("cannot allocate error storage", #curlocation)
    return request.address
}

private func __freeErrMemory(allocator: IAllocator, data: *void, size: u64)
{
    var request: AllocatorRequest
    request.address = data
    request.size    = Swag.max(size, 1'u64)
    allocator.free(&request)
}

private func __destroyErrArena(arena: *ErrorMessageArena)->*ErrorMessageLink?
{
    let allocator = arena.allocator
    let retained  = arena.retained
    arena.storage.release()
    __freeErrMemory(allocator, arena, #sizeof(ErrorMessageArena))
    return retained
}

private func __releaseErrArena(arena: *ErrorMessageArena)
{
    if arena.references.sub(1) != 1 do
        return
    __releaseErrMessages(__destroyErrArena(arena))
}

// While the originating context lives, its ScratchAllocator owns the ordinary bump buffer
// and tracked spills. Releasing it detaches those blocks into the arena, so worker teardown
// cannot invalidate a message still reachable through a transported error.
private func __detachErrMessages(storage: *ScratchAllocator)
{
    let arena = cast(*ErrorMessageArena) storage.releaseOwner!
    Swag.memcpy(&arena.storage, storage, #sizeof(ScratchAllocator))
    arena.storage.releaseOwner = null
    arena.storage.releaseHook  = null
    storage.releaseOwner       = null
    storage.releaseHook        = null
    storage.block              = null
    storage.firstLeak          = null
    storage.used               = 0
    storage.totalLeak          = 0
    __releaseErrArena(arena)
}

private func __errMessages(storage: *ScratchAllocator)->*ErrorMessageArena?
{
    if storage.releaseOwner do
        return cast(*ErrorMessageArena) storage.releaseOwner
    if not storage.block and not storage.firstLeak do
        return null

    let allocator = storage.allocator!
    let arena     = cast(*ErrorMessageArena) __allocateErrMemory(allocator, #sizeof(ErrorMessageArena))
    arena[] = ErrorMessageArena{allocator: allocator}
    arena.references.store(1)
    storage.releaseOwner = arena
    storage.releaseHook  = &__detachErrMessages
    return arena
}

private func __releaseErrMessages(first: *ErrorMessageLink?)
{
    var link = first
    var pending: *ErrorMessageLink?
    for
    {
        if link
        {
            let retired = link
            if retired.references.sub(1) != 1
            {
                link = null
            }
            else
            {
                let arena = retired.arena
                if arena.references.sub(1) == 1
                {
                    let retained = __destroyErrArena(arena)
                    if retained
                    {
                        // This link has no remaining readers. Reuse it as a continuation
                        // instead of recursing once per successful handled operation.
                        retired.releaseNext = pending
                        pending = retired
                        link    = retained
                        continue
                    }
                }

                let next = retired.next
                __freeErrMemory(retired.allocator, retired, #sizeof(ErrorMessageLink))
                link = next
                continue
            }
        }

        if not pending do
            return
        let resume = pending
        pending = resume.releaseNext
        link    = resume.next
        __freeErrMemory(resume.allocator, resume, #sizeof(ErrorMessageLink))
    }
}

// The incoming chain's reference is transferred into the new head, or returned unchanged
// when it already leases this arena. Sharing a head elsewhere requires its own reference.
private func __prependErrArena(messages: *ErrorMessageLink?, arena: *ErrorMessageArena, allocator: IAllocator)->*ErrorMessageLink
{
    var known = messages
    while known
    {
        if known.arena == arena do
            return messages!
        known = known.next
    }

    let link = cast(*ErrorMessageLink) __allocateErrMemory(allocator, #sizeof(ErrorMessageLink))
    link[] = ErrorMessageLink{allocator: allocator, arena: arena, next: messages}
    link.references.store(1)
    arena.references.add(1)
    return link
}

private func __retainErrFrameMessages(record: *ErrorRecord)
{
    let context = Swag.getContext()
    let current = __errMessages(&context.errorAllocator)
    if current do
        record.messages = __prependErrArena(record.messages, current, record.allocator)

    // A failure can refer to copied text made before its catch/expect operand began. Keep
    // those ancestor arenas too; their own context lease still protects unraised plain views.
    for index in context.errorIndex
    {
        let parent = __errMessages(&context.errors[index].pushErrorAllocator)
        if parent do
            record.messages = __prependErrArena(record.messages, parent, record.allocator)
    }
}

private func __finishErrStorage(context: *Context, failed: bool)
{
    if not context.errorIndex do
        return
    let current = &context.errorAllocator
    let parent  = &context.errors[context.errorIndex - 1].pushErrorAllocator
    if failed or (not current.block and not current.firstLeak and not current.releaseOwner)
    {
        // A failed operand's record already owns its new messages. End the context's lease
        // now; repeated dismissed failures then reclaim each arena at the last owner drop.
        current.release()
        Swag.memcpy(current, parent, #sizeof(ScratchAllocator))
        Swag.init(parent, 1)
        return
    }

    // Success can return a plain copied string. Keep its child buffer as current storage and
    // retain the older parent blocks from it, preserving both views until the enclosing frame
    // finishes. Empty child frames above avoid building an unnecessary arena chain.
    let parentArena = __errMessages(parent)
    if parentArena
    {
        let childArena = __errMessages(current)!
        childArena.retained = __prependErrArena(childArena.retained, parentArena, childArena.allocator)
    }

    parent.release()
}

func __releaseErrRecord(record: *ErrorRecord?)
{
    if not record or record.references.sub(1) != 1 do
        return
    let allocator = record.allocator
    let value     = record.value
    let size      = cast(u64) Swag.kindOf(value).sizeof
    __dropErr(value)
    __freeErrMemory(allocator, value.buffer!, size)
    __releaseErrMessages(record.messages)
    __freeErrMemory(allocator, record, #sizeof(ErrorRecord))
}

private func __findErrRecord(data: *void)->*ErrorRecord?
{
    let context = Swag.getContext()
    for &slot in context.errors
    {
        if slot.record and slot.value.buffer == data do
            return slot.record
    }

    var capture = context.errorCaptures
    while capture
    {
        if capture.record and capture.record.value.buffer == data do
            return capture.record
        capture = capture.next
    }

    return null
}

private func __copyErrRaw(data: *void, type: typeinfo, source: *ErrorRecord?)->*ErrorRecord
{
    let context = Swag.getContext()
    if not context.errorAllocator.capacity do
        context.errorAllocator.setCapacity(cast() __buildCfg.errorAllocatorCapacity, __runtimeAllocator())
    let allocator = context.errorAllocator.allocator!
    let record    = cast(*ErrorRecord) __allocateErrMemory(allocator, #sizeof(ErrorRecord))
    record[] = ErrorRecord{allocator: allocator}
    record.references.store(1)
    if source and source.messages
    {
        let messages = source.messages
        record.messages = messages
        messages.references.add(1)
    }

    let ptr = __allocateErrMemory(allocator, cast(u64) type.sizeof)
    Swag.memcpy(ptr, data, cast(u64) type.sizeof)
    if type is Swag.TypeInfoStruct as info
    {
        if info.opPostCopy do
            info.opPostCopy(ptr)
    }

    record.value = Swag.makeAny(ptr, type)
    __retainErrFrameMessages(record)
    return record
}

func __copyErrRecord(error: any)->*ErrorRecord
{
    return __copyErrRaw(error.buffer, Swag.kindOf(error), __findErrRecord(error.buffer))
}

func __copyOwnedErrRecord(source: *ErrorRecord)->*ErrorRecord
{
    return __copyErrRaw(source.value.buffer!, Swag.kindOf(source.value), source)
}

private func __installErrRecord(record: *ErrorRecord)
{
    let context = Swag.getContext()
    if context.errorIndex >= MaxErrors do
        Swag.panic("error propagation nesting exceeds its supported depth", #curlocation)
    let slot     = &context.errors[context.errorIndex]
    let previous = slot.record
    slot.record      = record
    slot.value       = record.value
    context.hasError = 1
    __releaseErrRecord(previous)
}

func __setOwnedErrRecord(source: *ErrorRecord)
{
    __installErrRecord(__copyOwnedErrRecord(source))
}

func __dropErr(err: any?)
{
    if err == null do
        return
    let data = err.buffer
    if Swag.kindOf(err) is Swag.TypeInfoStruct as type
    {
        if type.opDrop do
            type.opDrop(data)
    }
}

func __setErrRaw(data: *void, type: typeinfo)
{
    if type is Swag.TypeInfoNative as native where native.nativeKind == .Any
    {
        __setErr((cast(const *any) data)[])
        return
    }

    // Copy before releasing the old slot: a rethrow can read that very payload.
    __installErrRecord(__copyErrRaw(data, type, __findErrRecord(data)))
}

func __setErr(err: any)
{
    let data = err.buffer
    let type = Swag.kindOf(err)
    __setErrRaw(data, type)
}

func __hasErr()->bool => Swag.getContext().hasError != 0

// Whether a failure is in flight, which is what a 'defer #fail' runs on and a 'defer #nofail'
// stays out of.
func __isErrContext()->bool
{
    let cxt = Swag.getContext()
    if cxt.hasError != 0 or cxt.curError != null do
        return true

    // Cleanup that unwinds a failure runs with that failure parked one frame below. The flag
    // every fallible call is tested against has to be down for the duration, so the cleanup can
    // call fallible code and dismiss errors of its own, but the failure is still the reason the
    // cleanup is running and a '#fail' defer must see it.
    return cxt.errorIndex != 0 and cxt.errors[cxt.errorIndex - 1].pushHasError != 0
}

func __pushErr()
{
    let cxt   = Swag.getContext()
    let frame = &cxt.errors[cxt.errorIndex]
    Swag.memcpy(&frame.pushErrorAllocator, &cxt.errorAllocator, #sizeof(ScratchAllocator))
    Swag.init(&cxt.errorAllocator, 1)
    cxt.errorAllocator.allocator              = frame.pushErrorAllocator.allocator
    cxt.errorAllocator.capacity               = frame.pushErrorAllocator.capacity
    cxt.errors[cxt.errorIndex].pushTraceIndex = cast(u32) cxt.traceIndex
    cxt.errors[cxt.errorIndex].pushHasError   = cxt.hasError

    // The handler's ErrorCapture owns this view while nested cleanup runs.
    Swag.memcpy(&cxt.errors[cxt.errorIndex].pushCurError, &cxt.curError, #sizeof(any?))

    cxt.hasError   = 0
    cxt.curError   = null
    cxt.errorIndex += 1
}

func __popErr()
{
    let cxt    = Swag.getContext()
    let failed = cxt.hasError != 0
    let record = cxt.errors[cxt.errorIndex].record
    cxt.errors[cxt.errorIndex].record = null
    cxt.errors[cxt.errorIndex].value  = null
    __releaseErrRecord(record)
    __finishErrStorage(cxt, failed)

    cxt.errorIndex -= 1

    cxt.hasError = cxt.errors[cxt.errorIndex].pushHasError
    Swag.memcpy(&cxt.curError, &cxt.errors[cxt.errorIndex].pushCurError, #sizeof(any?))
    Swag.memset(&cxt.errors[cxt.errorIndex].pushCurError, 0, #sizeof(any?))
    cxt.traceIndex = cxt.errors[cxt.errorIndex].pushTraceIndex

    // The frame is no longer live, so what it recorded must not be read by the '#fail' lookup in
    // '__isErrContext': left set, it would answer for a frame that was popped long ago.
    cxt.errors[cxt.errorIndex].pushHasError = 0
}

// Kept as a runtime helper for callers that explicitly dismiss the ambient failure.
// Compiler-generated handlers use ErrorCapture.opDrop so every exit path also releases it.
func __endErr()
{
    Swag.getContext().curError = null
}

// The visible capture borrows a payload retained by its hidden lexical owner.
func __bindErr(dst: *(any?), owner: *ErrorCapture)
{
    let context = Swag.getContext()
    let handler = context.errorCaptures
    dst[] = null
    if not handler or not handler.handler or not handler.record do
        return
    let record = handler.record
    owner.record = record
    dst[]        = record.value
    record.references.add(1)
    __registerErrCapture(owner, context)
}

// Reset a 'catch e as err' capture slot before the fallible call runs, so a successful
// call leaves 'err' null (the failure path overwrites it via '__bindErr').
func __clearErr(dst: *(any?), owner: *ErrorCapture)
{
    owner.opDrop()
    dst[] = null
}

private func __registerErrCapture(owner: *ErrorCapture, context: *Context)
{
    owner.context = context
    owner.next    = context.errorCaptures
    if owner.next do
        owner.next.previous = owner
    context.errorCaptures = owner
}

func __catchErr(owner: *ErrorCapture)
{
    let context = Swag.getContext()
    owner.handler = context.hasError != 0
    if context.errorIndex do
        owner.previousError = context.errors[context.errorIndex - 1].pushCurError
    let slot = &context.errors[context.errorIndex]
    if context.hasError
    {
        let record = slot.record!
        owner.record = record

        // Failure defers can have added or merged message storage since the error was raised.
        __retainErrFrameMessages(record)
        context.curError = slot.value
    }
    else
    {
        context.curError = owner.previousError
        __releaseErrRecord(slot.record)
    }

    slot.record = null
    slot.value  = null
    __finishErrStorage(context, owner.handler)
    context.hasError = 0
    if context.errorIndex
    {
        context.errorIndex -= 1
        context.errors[context.errorIndex].pushHasError = 0
        context.errors[context.errorIndex].pushCurError = null
    }

    __registerErrCapture(owner, context)
}

// Context shutdown can still encounter an unconsumed raised value after a panic/test reset.
// Lexical captures normally have left already; detaching the message allocator below keeps
// any explicitly transported record alive independently of this context.
func __releaseErrContext(context: *Context)
{
    for &slot in context.errors
    {
        let record = slot.record
        slot.record       = null
        slot.value        = null
        slot.pushCurError = null
        slot.pushHasError = 0
        __releaseErrRecord(record)
    }

    context.curError   = null
    context.hasError   = 0
    context.errorIndex = 0
    for &slot in context.errors do
        slot.pushErrorAllocator.release()
    context.errorAllocator.release()
}

// Native test recovery abandons the failed stack instead of unwinding it. Consume its lexical
// owners while their addresses are still live; a later test must never inspect that old stack.
func __abandonErrCaptures(context: *Context)
{
    while context.errorCaptures
    {
        let capture = context.errorCaptures
        context.errorCaptures = capture.next
        capture.opDrop()
    }

    __releaseErrContext(context)
}

func __failedExpect(loc: SourceCodeLocation)
{
    let cxt  = Swag.getContext()
    let type = Swag.kindOf(cxt.errors[cxt.errorIndex].value)

    var str: [512] u8
    var len: u64

    const U = "uncaught runtime error "
    Swag.memcpy(&str[len], U.buffer, U.count)
    len += U.count
    var maxLen = Swag.min(type.fullname.count, 128)
    str[len] = '['
    len      += 1
    str[len] = '['
    len      += 1
    Swag.memcpy(&str[len], type.fullname.buffer, maxLen)
    len      += maxLen
    str[len] = ']'
    len      += 1
    str[len] = ']'
    len      += 1

    if type is Swag.TypeInfoStruct as typeStruct
    {
        let fields = typeStruct.fields
        if (fields != null and fields.count > 0 and fields[0].pointedType == Swag.BaseError) or
           (type == Swag.BaseError)
        {
            let data = (cxt.errors[cxt.errorIndex].value).buffer
            let val  = cast(const *Swag.BaseError) data!
            maxLen = Swag.min(val.message.count, 128)
            if maxLen
            {
                str[len] = ' '
                len      += 1
                str[len] = '$'
                len      += 1
                str[len] = ' '
                len      += 1
                Swag.memcpy(&str[len], val.message.buffer, maxLen)
                len += maxLen
            }
        }
    }

    cxt.hasError = 0

    str[len] = 0
    Swag.panic(Swag.makeString(&str[0], len), loc)

    // A hook may report or transfer control, but it cannot resume a failed 'expect'.
    __exitError()
}

////////////////////////////////////////////////////////////

func __stackTrace(loc: SourceCodeLocation)
{
    let cxt = Swag.getContext()
    if cxt.traceIndex >= MaxTraces do
        return
    cxt.traces[cxt.traceIndex] = loc
    cxt.traceIndex += 1
}

////////////////////////////////////////////////////////////

// Raise a compiler error at the given source location
func compilerError(message: string, loc: SourceCodeLocation)
{
    if Swag.jit()
    {
        __raiseException666(message, loc, .Error)
        return
    }
}

// Raise a compiler warning at the given source location
func compilerWarning(message: string, loc: SourceCodeLocation)
{
    if Swag.jit()
    {
        __raiseException666(message, loc, .Warning)
        return
    }
}

// Print a full panic report: banner, message, source location and both stack traces.
// Shared by the default panic path below and by the native #test runner, whose panic
// hook reports a failing test with the exact same output before resuming the runner.
func __printPanicReport(message: string?, loc: SourceCodeLocation)
{
    let cxt = Swag.getContext()

    Swag.print("\nruntime panic\n")
    Swag.print("-------------\n")
    Swag.print("message: ", message, "\n")
    Swag.print("source:  ")
    Swag.print(loc.fileName, ":", loc.lineStart, ":", loc.colStart, "\n")
    Swag.print("\n")

    // Print the error stack trace if available
    if cxt.traceIndex
    {
        Swag.print("error trace\n")
        for var i = cast(s32) cxt.traceIndex - 1; i >= 0; i -= 1
        {
            Swag.print("  originates at ")
            Swag.print(cxt.traces[i].fileName)
            Swag.print(":")
            Swag.print(cast(s64) cxt.traces[i].lineStart)
            Swag.print(":")
            Swag.print(cast(s64) cxt.traces[i].colStart)
            Swag.print("\n")
        }

        Swag.print("\n")
    }

    // The panic entry captures before calling a user hook. Capturing from the hook itself stops at
    // the panic frame on Windows and loses the application caller, which made devmode reports no
    // more useful than release reports. A direct internal call still has a local fallback.
    var fallback: [64] (*void?) = cast(*void?) null
    var trace = Swag.makeSlice(&cxt.panicStack[0], cxt.panicStackCount)
    if not cxt.panicStackCount
    {
        let count = __captureStack(1, fallback)
        trace = Swag.makeSlice(&fallback[0], count)
    }

    if __hasStackTraceSymbols(trace)
    {
        Swag.print("runtime trace\n")
        __logStackTrace(trace)
        Swag.print("\n")
    }

    cxt.panicStackCount = 0
}

// Stop the execution and panic
#[Swag.Safety(.All, false)]
func panic(message: string?, loc: SourceCodeLocation)
{
    // Capture while the application caller is still immediately above this frame. A panic hook is
    // free to resume execution (the native test runner does). Store it in the process context so a
    // hook compiled into another Swag module sees the same capture.
    let cxt = Swag.getContext()
    cxt.panicStackCount = __captureStack(0, cxt.panicStack)

    // User function
    if cxt.panic
    {
        cxt.panic(message, loc)
        return
    }

    // If we are running bytecode, then just let the runner deal with the message,
    // we will have more usefull information
    if Swag.jit()
    {
        __raiseException666(message, loc, .Panic)
        return
    }

    // A panic reports a broken invariant, so the process stops here. Returning
    // would resume the caller on state the panic just declared unusable, and the
    // run would end with a success code that hides the report printed above.
    __printPanicReport(message, loc)
    __exitError()
}

#[Swag.Safety(.All, false)]
func safetyPanic(message: string, loc: SourceCodeLocation)
{
    if Swag.jit()
    {
        __raiseException666(message, loc, .Safety)
        return
    }

    Swag.panic(message, loc)
}

func __panic(file: const [*] u8, line: u32, col: u32, message: const [*] u8?)
{
    var loc: SourceCodeLocation
    loc.fileName = Swag.makeString(file, (cast(const cstring) file).count)
    loc.lineStart, loc.lineEnd = line
    loc.colStart, loc.colEnd   = col

    let msg = message ? Swag.makeString(message, (cast(const cstring) message).count) : "panic"
    Swag.panic(msg, loc)
}

func __compilerError(file: const [*] u8, line: u32, col: u32, message: const [*] u8?)
{
    var loc: SourceCodeLocation
    loc.fileName = Swag.makeString(file, (cast(const cstring) file).count)
    loc.lineStart, loc.lineEnd = line
    loc.colStart, loc.colEnd   = col

    let msg = message ? Swag.makeString(message, (cast(const cstring) message).count) : "compiler error"
    Swag.compilerError(msg, loc)
}
