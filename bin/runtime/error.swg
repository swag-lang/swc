using Swag

////////////////////////////////////////////////////////////

func __dropErr(err: #null any)
{
    if err == null do
        return
    let data = err.buffer
    let type = cast(const *Swag.TypeInfoStruct) Swag.kindOf(err)
    if type.opDrop do
        type.opDrop(data)
}

func __setErrRaw(data: *void, type: const *Swag.TypeInfoStruct)
{
    if type.kind == .Native and (cast(const *Swag.TypeInfoNative) type).nativeKind == .Any
    {
        __setErr(data[as any])
        return
    }

    let cxt = Swag.getContext()
    if cxt.errorIndex >= MaxErrors do
        Swag.panic("error propagation nesting exceeds its supported depth", #curlocation)

    __dropErr(cxt.errors[cxt.errorIndex].value)

    // We check that the contextual error allocator has been initialized.
    // In case an error is raised at a very very early stage (in #init)
    if !cxt.errorAllocator.capacity do
        cxt.errorAllocator.setCapacity(cast() __buildCfg.errorAllocatorCapacity, __runtimeAllocator())

    let ptr = cxt.errorAllocator.alloc(cast(u64) type.sizeof)
    Swag.memcpy(ptr, data, cast(u64) type.sizeof)
    if type.opPostCopy do
        type.opPostCopy(ptr)
    cxt.errors[cxt.errorIndex].value = Swag.makeAny(ptr, type)
    cxt.hasError = 1
}

func __setErr(err: any)
{
    let data = err.buffer
    let type = cast(const *Swag.TypeInfoStruct) Swag.kindOf(err)
    __setErrRaw(data, type)
}

func __hasErr()->bool
{
    return Swag.getContext().hasError != 0
}

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
    let cxt = Swag.getContext()
    cxt.errors[cxt.errorIndex].pushTraceIndex = cast(u32) cxt.traceIndex
    cxt.errors[cxt.errorIndex].pushUsedAlloc  = cast(u32) cxt.errorAllocator.used
    cxt.errors[cxt.errorIndex].pushHasError   = cxt.hasError

    // This is a borrowed bitwise snapshot. The owning error value stays in its scratch slot; a
    // normal assignment here would give the snapshot an ownership lifecycle of its own.
    Swag.memcpy(&cxt.errors[cxt.errorIndex].pushCurError, &cxt.curError, #sizeof(#null any))

    cxt.hasError   = 0
    cxt.curError   = null
    cxt.errorIndex += 1
}

func __popErr()
{
    let cxt = Swag.getContext()
    __dropErr(cxt.errors[cxt.errorIndex].value)
    cxt.errors[cxt.errorIndex].value = null

    cxt.errorIndex -= 1

    cxt.hasError = cxt.errors[cxt.errorIndex].pushHasError
    Swag.memcpy(&cxt.curError, &cxt.errors[cxt.errorIndex].pushCurError, #sizeof(#null any))
    Swag.memset(&cxt.errors[cxt.errorIndex].pushCurError, 0, #sizeof(#null any))
    cxt.traceIndex          = cxt.errors[cxt.errorIndex].pushTraceIndex
    cxt.errorAllocator.used = cxt.errors[cxt.errorIndex].pushUsedAlloc

    // The frame is no longer live, so what it recorded must not be read by the '#fail' lookup in
    // '__isErrContext': left set, it would answer for a frame that was popped long ago.
    cxt.errors[cxt.errorIndex].pushHasError = 0
}

// Dismiss the error a 'catch' handler or 'as err' capture just dealt with: after it runs
// (with the error still in curError), clear it so it no longer counts as in-flight for
// '#fail'/'#nofail' defers. 'catchErr' already popped the error frame, so only the
// current-error pointer remains to be cleared.
func __endErr()
{
    Swag.getContext().curError = null
}

// Seed the 'catch e as err { H }' binding: copy the current error into the caller-provided
// slot right before the handler runs (curError is still valid at that point, cleared by
// '__endErr' only after H). All the fat-value copy lives here so codegen just passes the slot.
func __bindErr(dst: *#null any)
{
    dst[] = Swag.getContext().curError
}

// Reset a 'catch e as err' capture slot before the fallible call runs, so a successful
// call leaves 'err' null (the failure path overwrites it via '__bindErr').
func __clearErr(dst: *#null any)
{
    dst[] = null
}

func __catchErr()
{
    let cxt = Swag.getContext()
    if !cxt.hasError do
        cxt.curError = null
    else do
        cxt.curError = cxt.errors[cxt.errorIndex].value
    cxt.errorAllocator.used = cxt.errorIndex ? cxt.errors[cxt.errorIndex - 1].pushUsedAlloc : 0
    cxt.hasError            = 0
    if cxt.errorIndex
    {
        cxt.errorIndex -= 1
        cxt.errors[cxt.errorIndex].pushHasError = 0
    }
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

    if type.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *Swag.TypeInfoStruct) type
        let fields     = typeStruct.fields
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
}

////////////////////////////////////////////////////////////

func __stackTrace(loc: SourceCodeLocation)
{
    let cxt = Swag.getContext()
    if cxt.traceIndex >= MaxTraces do
        return
    cxt.traces[cxt.traceIndex] = loc
    cxt.traceIndex             += 1
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
func __printPanicReport(message: #null string, loc: SourceCodeLocation)
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
    var fallback: [64] *void = undefined
    var trace                = Swag.makeSlice(&cxt.panicStack[0], cxt.panicStackCount)
    if !cxt.panicStackCount
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
func panic(message: #null string, loc: SourceCodeLocation)
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

func __panic(file: const [*] u8, line: u32, col: u32, message: #null const [*] u8)
{
    var loc: SourceCodeLocation
    loc.fileName               = Swag.makeString(file, (cast(const cstring) file).count)
    loc.lineStart, loc.lineEnd = line
    loc.colStart, loc.colEnd   = col

    let msg = message ? Swag.makeString(message, (cast(const cstring) message).count) : "panic"
    Swag.panic(msg, loc)
}

func __compilerError(file: const [*] u8, line: u32, col: u32, message: #null const [*] u8)
{
    var loc: SourceCodeLocation
    loc.fileName               = Swag.makeString(file, (cast(const cstring) file).count)
    loc.lineStart, loc.lineEnd = line
    loc.colStart, loc.colEnd   = col

    let msg = message ? Swag.makeString(message, (cast(const cstring) message).count) : "compiler error"
    Swag.compilerError(msg, loc)
}
