#global if #os == Swag.TargetOs.Linux

namespace __LinuxRT
{
    #[Swag.CallingConvention(.C)]
    alias ThreadEntry = func(*void?)->u32
    #[Swag.CallingConvention(.C)]
    alias PthreadEntry = func(*void?)->*void?

    struct ScheduleParameter { priority: s32 }

    #[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
    {
        func pthread_create(thread: *u64, attributes: const *void?, entry: PthreadEntry, parameter: *void?)->s32
        func pthread_join(thread: u64, result: *(*void?)?)->s32
        func pthread_self()->u64
        func pthread_getschedparam(thread: u64, policy: *s32, parameter: *ScheduleParameter)->s32
        func pthread_setschedparam(thread: u64, policy: s32, parameter: const *ScheduleParameter)->s32
        func sched_getaffinity(process: s32, size: u64, mask: *void)->s32
        func getenv(name: const [*] u8)->const [*] u8?
        func write(descriptor: s32, buffer: const *void, count: u64)->s64
        func read(descriptor: s32, buffer: *void, count: u64)->s64
        func dlopen(path: const [*] u8, flags: s32)->*void?
        func backtrace(buffer: *(*void?), count: s32)->s32
        func __sigsetjmp(storage: *void, saveMask: s32)->s32
        #[Swag.NoReturn]
        func siglongjmp(storage: *void, value: s32)
        #[Swag.NoReturn]
        func exit(status: s32)
        #[Swag.NoReturn]
        func _exit(status: s32)
    }
}

private struct LinuxThreadStart
{
    entry: __LinuxRT.ThreadEntry
    parameter: *void?
}

#[Swag.CallingConvention(.C)]
private func __linuxThreadStart(parameter: *void?)->*void?
{
    let start = cast(*LinuxThreadStart, parameter)
    let entry = start.entry
    let argument = start.parameter
    Swag.__bootstrapFree(cast([*] void, start))
    discard entry(argument)
    return null
}

func __hostThreadCreate(entry: __LinuxRT.ThreadEntry, param: *void?)->*void?
{
    let memory = Swag.__bootstrapAlloc(#sizeof(LinuxThreadStart))
    if not memory do
        return null
    let start = cast(*LinuxThreadStart, memory)
    start.entry = entry
    start.parameter = param
    var thread: u64
    if __LinuxRT.pthread_create(&thread, null, &__linuxThreadStart, start) != 0
    {
        Swag.__bootstrapFree(cast([*] void, start))
        return null
    }
    return cast(*void, thread)
}

func __hostThreadJoin(handle: *void?)
{
    if handle do
        discard __LinuxRT.pthread_join(cast(u64, handle), null)
}

// BATCH is reversible without privilege; nice increments cannot safely implement restoration.
func __hostThreadEnterBackground()->s32
{
    var policy: s32
    var parameter: __LinuxRT.ScheduleParameter
    let thread = __LinuxRT.pthread_self()
    if __LinuxRT.pthread_getschedparam(thread, &policy, &parameter) != 0 or (policy != 0 and policy != 3) do
        return -1
    if __LinuxRT.pthread_setschedparam(thread, 3, &parameter) != 0 do
        return -1
    return policy
}

func __hostThreadLeaveBackground(previous: s32)
{
    if previous < 0 do
        return
    let parameter = __LinuxRT.ScheduleParameter{}
    discard __LinuxRT.pthread_setschedparam(__LinuxRT.pthread_self(), previous, &parameter)
}

func __hostProcessorCount()->u32
{
    var mask: [1024] u8
    if __LinuxRT.sched_getaffinity(0, #sizeof(mask), &mask[0]) != 0 do
        return 1
    var count = 0'u32
    for byte in mask
    {
        var remaining = byte
        while remaining
        {
            count += 1
            remaining &= remaining - 1
        }
    }
    return count == 0 ? 1 : count
}

func __hostRuntimeThreadLimit()->u32
{
    let text = __LinuxRT.getenv("SWAG_RUNTIME_THREADS".buffer)
    let value = text ? Swag.makeString(text, cast(const cstring, text).count) : ""
    let (limit, valid) = Swag.parseRuntimeThreadLimit(value)
    if valid do
        return limit
    Swag.panic("SWAG_RUNTIME_THREADS accepts 1 to 10 decimal digits with a value from 0 through 4294967295", #curlocation)
}

func __printString(message: string?)
{
    if not message do
        return
    var offset = 0'u64
    while offset < message.count
    {
        let written = __LinuxRT.write(1, &message.buffer[offset], message.count - offset)
        if written > 0 do
            offset += cast(u64, written)
        elif written == 0 or __LinuxRT.__errno_location()[] != __LinuxRT.Interrupted do
            return
    }
}

func __loaddll(name: string) => __LinuxRT.dlopen(name.buffer, 2)

#[Swag.NoReturn]
func __exit() { __LinuxRT.exit(0) }
#[Swag.NoReturn]
func __exitError() { __LinuxRT.exit(-666) }
#[Swag.NoReturn]
func __hostTestAbort() { __LinuxRT._exit(-666) }

// glibc x86-64 sigjmp_buf is 200 bytes aligned to eight bytes. The caller retains the
// entire storage while the captured frame is live; no C++ frame is crossed by native recovery.
const HostResumeStorageSize = 200 + 7

private func __linuxResumeStorage(storage: *u8)->*void => cast(*void, (cast(u64, storage) + 7) & ~7'u64)

#[Swag.Optimize(false)]
func __hostCatchCall(storage: *u8, resumed: *bool, fn: func||())
{
    discard resumed
    if __LinuxRT.__sigsetjmp(__linuxResumeStorage(storage), 1) != 0 do
        return
    fn()
}

#[Swag.NoReturn]
func __hostResume(storage: *u8)
{
    __LinuxRT.siglongjmp(__linuxResumeStorage(storage), 1)
}

private var linuxTestResume: [HostResumeStorageSize] u8

#[Swag.Optimize(false)]
func __hostTestCall(fn: *void)
{
    if __LinuxRT.__sigsetjmp(__linuxResumeStorage(&linuxTestResume[0]), 1) != 0 do
        return
    let call = cast(func(), fn)
    call()
}

#[Swag.NoReturn]
func __hostTestResume()
{
    Swag.__valueBorrowReset()
    __hostResume(&linuxTestResume[0])
}

func __captureStack(skip: u32, wh: [..] (*void?))->u32
{
    var frames: [128] (*void?)
    let captured = __LinuxRT.backtrace(&frames[0], cast(s32, frames.count))
    if captured <= 0 or cast(u64, skip) + 1 >= cast(u64, captured) do
        return 0
    let count = Swag.min(wh.count, cast(u64, captured) - cast(u64, skip) - 1)
    Swag.memcpy(wh.buffer, &frames[skip + 1], count * #sizeof(*void?))
    return cast(u32, count)
}

#[Swag.Safety(.ValueBorrow, false)]
func __raiseException666(message: string?, loc: Swag.SourceCodeLocation, kind: Swag.ExceptionKind)
{
    let context = Swag.getContext()
    if kind == .Assert and context.panicCatch do
        Swag.panic(message, loc)
    if not Swag.jit() do
        Swag.panic(message, loc)

    context.exceptionLoc = loc
    context.exceptionParams[0] = cast(const *void, &context.exceptionLoc)
    context.exceptionParams[1] = cast(const *void?, message.buffer)
    context.exceptionParams[2] = cast(const *void, message.count)
    context.exceptionParams[3] = cast(const *void, cast(u64, kind))
    Swag.__valueBorrowReset()
    if context.compilerRaise
    {
        context.compilerRaise(context)
        return
    }

    __printString(message)
    __exitError()
}
