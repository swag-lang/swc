using Swag

////////////////////////////////////////////////////////////

func __dropErr(err: #null any)
{
    if err == null do
        return
    let data = @dataof(err)
    let type = cast(const *Swag.TypeInfoStruct) @kindof(err)
    if type.opDrop do
        type.opDrop(data)
}

func __setErrRaw(data: *void, type: const *Swag.TypeInfoStruct)
{
    if type.kind == .Native and (cast(const *Swag.TypeInfoNative) type).nativeKind == .Any
    {
        __setErr(dref cast(*any) data)
        return
    }

    let cxt = @getcontext()
    if cxt.errorIndex >= MaxErrors do
        @panic("error propagation nesting exceeds its supported depth", #curlocation)

    __dropErr(cxt.errors[cxt.errorIndex].value)

    // We check that the contextual error allocator has been initialized.
    // In case an error is raised at a very very early stage (in #init)
    if !cxt.errorAllocator.capacity do
        cxt.errorAllocator.setCapacity(cast() __buildCfg.errorAllocatorCapacity, __runtimeAllocator())

    let ptr  = cxt.errorAllocator.alloc(cast(u64) type.sizeof)
    @memcpy(ptr, data, cast(u64) type.sizeof)
    if type.opPostCopy do
        type.opPostCopy(ptr)
    cxt.errors[cxt.errorIndex].value = @mkany(ptr, type)
    cxt.hasError                     = 1
}

func __setErr(err: any)
{
    let data = @dataof(err)
    let type = cast(const *Swag.TypeInfoStruct) @kindof(err)
    __setErrRaw(data, type)
}

func __hasErr()->bool
{
    return @getcontext().hasError != 0
}

func __isErrContext()->bool
{
    let cxt = @getcontext()
    return cxt.hasError != 0 or cxt.curError != null
}

func __pushErr()
{
    let cxt = @getcontext()
    cxt.errors[cxt.errorIndex].pushTraceIndex = cast(u32) cxt.traceIndex
    cxt.errors[cxt.errorIndex].pushUsedAlloc  = cast(u32) cxt.errorAllocator.used
    cxt.errors[cxt.errorIndex].pushHasError   = cxt.hasError

    cxt.hasError   = 0
    cxt.curError   = null
    cxt.errorIndex += 1
}

func __popErr()
{
    let cxt = @getcontext()
    __dropErr(cxt.errors[cxt.errorIndex].value)
    cxt.errors[cxt.errorIndex].value = null

    cxt.errorIndex -= 1

    cxt.hasError            = cxt.errors[cxt.errorIndex].pushHasError
    cxt.curError            = cxt.errors[cxt.errorIndex].value
    cxt.traceIndex          = cxt.errors[cxt.errorIndex].pushTraceIndex
    cxt.errorAllocator.used = cxt.errors[cxt.errorIndex].pushUsedAlloc
}

func __catchErr()
{
    let cxt = @getcontext()
    if !cxt.hasError do
        cxt.curError = null
    else do
        cxt.curError        = cxt.errors[cxt.errorIndex].value
    cxt.errorAllocator.used = cxt.errorIndex ? cxt.errors[cxt.errorIndex - 1].pushUsedAlloc : 0
    cxt.hasError            = 0
    if cxt.errorIndex do
        cxt.errorIndex -= 1
}

// Returns the current raised error, or null if none
#[Swag.Inline]
func @err()->#null any
{
    let cxt = @getcontext()
    return cxt.curError
}

func __failedAssume(loc: SourceCodeLocation)
{
    let cxt  = @getcontext()
    let type = @kindof(cxt.errors[cxt.errorIndex].value)

    var str: [512] u8
    var len: u64

    const U = "uncatched runtime error "
    @memcpy(&str[len], @dataof(U), @countof(U))
    len += @countof(U)
    var maxLen = @min(@countof(type.fullname), 128)
    str[len] = '['
    len      += 1
    str[len] = '['
    len      += 1
    @memcpy(&str[len], @dataof(type.fullname), maxLen)
    len      += maxLen
    str[len] = ']'
    len      += 1
    str[len] = ']'
    len      += 1

    if type.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *Swag.TypeInfoStruct) type
        let fields     = typeStruct.fields
        if (fields != null and @countof(fields) > 0 and fields[0].pointedType == Swag.BaseError) or
           (type == Swag.BaseError)
        {
            let data = @dataof(cxt.errors[cxt.errorIndex].value)
            let val  = cast(const *Swag.BaseError) notnull data
            maxLen = @min(@countof(val.message), 128)
            if maxLen
            {
                str[len] = ' '
                len      += 1
                str[len] = '$'
                len      += 1
                str[len] = ' '
                len      += 1
                @memcpy(&str[len], @dataof(val.message), maxLen)
                len += maxLen
            }
        }
    }

    cxt.hasError = 0

    str[len] = 0
    @panic(@mkstring(&str[0], len), loc)
}

////////////////////////////////////////////////////////////

func __stackTrace(loc: SourceCodeLocation)
{
    let cxt = @getcontext()
    if cxt.traceIndex >= MaxTraces do
        return
    cxt.traces[cxt.traceIndex] = loc
    cxt.traceIndex             += 1
}

////////////////////////////////////////////////////////////

// Raise a compiler error at the given source location
func @compilererror(message: string, loc: SourceCodeLocation)
{
    if @jit
    {
        __raiseException666(message, loc, .Error)
        return
    }
}

// Raise a compiler warning at the given source location
func @compilerwarning(message: string, loc: SourceCodeLocation)
{
    if @jit
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
    let cxt = @getcontext()

    @print("\nruntime panic\n")
    @print("-------------\n")
    @print("message: ", message, "\n")
    @print("source:  ")
    @print(loc.fileName, ":", loc.lineStart + 1, ":", loc.colStart + 1, "\n")
    @print("\n")

    // Print the error stack trace if available
    if cxt.traceIndex
    {
        @print("error trace\n")
        for var i = cast(s32) cxt.traceIndex - 1; i >= 0; i -= 1
        {
            @print("  originates at ")
            @print(cxt.traces[i].fileName)
            @print(":")
            @print(cast(s64) cxt.traces[i].lineStart + 1)
            @print(":")
            @print(cast(s64) cxt.traces[i].colStart + 1)
            @print("\n")
        }

        @print("\n")
    }

    // Print the calling stack trace
    @print("runtime trace\n")
    var arr: [64] *void = undefined
    let nb   = __captureStack(1, arr)
    __logStackTrace(@mkslice(&arr[0], nb))
    @print("\n")
}

// Stop the execution and panic
#[Swag.Safety(.All, false)]
func @panic(message: #null string, loc: SourceCodeLocation)
{
    let cxt = @getcontext()

    // User function
    if cxt.panic
    {
        cxt.panic(message, loc)
        return
    }

    // If we are running bytecode, then just let the runner deal with the message,
    // we will have more usefull information
    if @jit
    {
        __raiseException666(message, loc, .Panic)
        return
    }

    __printPanicReport(message, loc)

    for arg in @args
    {
        if @stringcmp(arg, "swag.test") do
            __exitError()
    }

    // Build message
    var str: [1024] u8
    var len: u64

    if message != null
    {
        len = @countof(message)
        if len > 512 do
            len = 512
        @memcpy(&str[0], @dataof(message), len)
        str[len]     = '\n'
        str[len + 1] = '\n'
        len          += 2
    }

    // Source location
    @memcpy(&str[len], @dataof(loc.fileName), @countof(loc.fileName))
    len += @countof(loc.fileName)
    @memcpy(&str[len], @dataof(", line "), 7)
    len += 7
    let dstLine = cast([*] u8) &str[len]
    let cptLine = cast(u32) (__itoa(dstLine, cast(s64) loc.lineStart + 1) - dstLine)
    len += cptLine
    @memcpy(&str[len], @dataof("\n\n"), 2)
    len += 2

    // Message to the user
    const title = "Swag runtime panic"
    const info  = """Cancel: exit the program
Retry: break into the debugger
Continue: ignore the panic
"""

    @memcpy(&str[len], @dataof(info), @countof(info))
    len += @countof(info)

    str[len] = 0

//__panicBox(cast(string) str, title)
}

#[Swag.Safety(.All, false)]
func @safetypanic(message: string, loc: SourceCodeLocation)
{
    if @jit
    {
        __raiseException666(message, loc, .Safety)
        return
    }

    @panic(message, loc)
}

func __panic(file: const [*] u8, line: u32, col: u32, message: const [*] u8)
{
    var loc: SourceCodeLocation
    loc.fileName               = @mkstring(file, @countof(cast(const cstring) file))
    loc.lineStart, loc.lineEnd = line
    loc.colStart, loc.colEnd   = col

    let msg = message ? @mkstring(message, @countof(cast(const cstring) message)) : "panic"
    @panic(msg, loc)
}

func __compilerError(file: const [*] u8, line: u32, col: u32, message: const [*] u8)
{
    var loc: SourceCodeLocation
    loc.fileName               = @mkstring(file, @countof(cast(const cstring) file))
    loc.lineStart, loc.lineEnd = line
    loc.colStart, loc.colEnd   = col

    let msg = message ? @mkstring(message, @countof(cast(const cstring) message)) : "compiler error"
    @compilererror(msg, loc)
}
