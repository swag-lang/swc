#global if #os == Swag.TargetOs.Linux

namespace __LinuxRT
{
    // glibc x86-64 layouts, distinct from the kernel's compact rt_sigaction ABI.
    struct SignalAction
    {
        handler: *void?
        mask: [16] u64
        flags: u32
        restorer: *void?
    }

    struct SignalStack
    {
        address: *void?
        flags: s32
        size: u64
    }

    struct SignalInfo
    {
        signal: s32
        error: s32
        code: s32
        padding: u32
        address: *void?
    }

    // Only the prefix through the machine's general-purpose registers is accessed.
    struct SignalContext
    {
        flags: u64
        link: *void?
        stack: SignalStack
        registers: [23] u64
    }

    #[Swag.CallingConvention(.C)]
    alias SignalHandler = func(s32)
    #[Swag.CallingConvention(.C)]
    alias SignalInfoHandler = func(s32, *SignalInfo, *SignalContext)

    #[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
    {
        func sigaction(signal: s32, action: const *SignalAction?, previous: *SignalAction?)->s32
        func sigaltstack(stack: const *SignalStack?, previous: *SignalStack?)->s32
        func sigprocmask(operation: s32, mask: const *void?, previous: *void?)->s32
        func raise(signal: s32)->s32
        func __sigsetjmp(storage: *void, saveMask: s32)->s32
        #[Swag.NoReturn]
        func siglongjmp(storage: *void, value: s32)
    }
}

private const LinuxFaultSignals = [11's32, 7's32, 4's32, 8's32] // SEGV, BUS, ILL, FPE
private const LinuxSignalInfo = 4'u32
private const LinuxSignalOnStack = 0x08000000'u32
private const LinuxSignalResetHand = 0x80000000'u32

private struct LinuxTestFilter
{
    previous: [4] __LinuxRT.SignalAction
    consumed: [4] u32
    previousStack: __LinuxRT.SignalStack
    mapping: *void?
    mappingSize: u64
    stackTop: u64
    installed: u32
    active: bool
    recovering: bool
    code: u32
    instruction: u64
    accessKind: u64
    address: u64
}

private var linuxTestFilter: LinuxTestFilter

// The signal returns through the kernel before this entry runs on the reserved stack.
// Reporting and panic cleanup may allocate or lock; neither belongs in a signal handler.
// The interrupted stack remains intact until catchPanic or the test runner resumes it.
#[Swag.CallingConvention(.C), Swag.NoReturn]
private func __linuxTestFaultTrampoline()
{
    Swag.__testHardwareException(linuxTestFilter.code, linuxTestFilter.instruction,
                                linuxTestFilter.accessKind, linuxTestFilter.address)
    __hostTestAbort()
}

#[Swag.NoReturn, Swag.Safety(.ValueBorrow, false)]
private func __linuxTerminateSignal(signal: s32)
{
    var action: __LinuxRT.SignalAction
    discard __LinuxRT.sigaction(signal, &action, null)
    discard __LinuxRT.raise(signal)
    var mask: [16] u64
    mask[0] = 1'u64 << cast(u32, signal - 1)
    discard __LinuxRT.sigprocmask(1, &mask, null) // SIG_UNBLOCK delivers the pending default action.
    __LinuxRT._exit(128 + signal)
}

#[Swag.CallingConvention(.C), Swag.Safety(.ValueBorrow, false)]
private func __linuxTestSignal(signal: s32, info: *__LinuxRT.SignalInfo, context: *__LinuxRT.SignalContext)
{
    if linuxTestFilter.active and Swag.g_TestRunning and info.code > 0 and
       __hostCurrentThreadId() == Swag.g_TestThreadId
    {
        if linuxTestFilter.recovering do
            __linuxTerminateSignal(signal)
        linuxTestFilter.recovering = true
        linuxTestFilter.code = signal == 11 or signal == 7 ? 0xC0000005'u32 : cast(u32, signal)
        linuxTestFilter.instruction = context.registers[16] // REG_RIP
        linuxTestFilter.address = cast(u64, info.address)
        let pageError = context.registers[19] // REG_ERR: page-fault write and instruction-fetch bits.
        linuxTestFilter.accessKind = (pageError & 16) != 0 ? 8 : (pageError & 2) != 0 ? 1 : 0
        context.registers[15] = linuxTestFilter.stackTop // REG_RSP, aligned as a System V call entry.
        context.registers[16] = cast(u64, cast(*void, &__linuxTestFaultTrampoline))
        return
    }

    // Preserve the embedding process's handlers for asynchronous signals and other threads.
    for index in 4'u32 where LinuxFaultSignals[index] == signal
    {
        let previous = &linuxTestFilter.previous[index]
        let handler = cast(u64, previous.handler)
        if handler == 1 and info.code <= 0 do
            return
        if handler > 1
        {
            if (previous.flags & LinuxSignalResetHand) != 0 and
               Swag.atomicExchange(&linuxTestFilter.consumed[index], 1) != 0 do
                __linuxTerminateSignal(signal)
            if (previous.flags & LinuxSignalInfo) != 0
            {
                let call = cast(__LinuxRT.SignalInfoHandler, unwrap previous.handler)
                call(signal, info, context)
            }
            else
            {
                let call = cast(__LinuxRT.SignalHandler, unwrap previous.handler)
                call(signal)
            }
            return
        }
    }
    __linuxTerminateSignal(signal)
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostTestRestoreHardwareFilter(previous: *void?)
{
    if previous != cast(*void, &linuxTestFilter) do
        __hostTestAbort()
    linuxTestFilter.active = false
    for index in linuxTestFilter.installed
    {
        // A one-shot handler consumed while ours was installed must stay consumed.
        var action = linuxTestFilter.previous[index]
        if linuxTestFilter.consumed[index] != 0 do
            action.handler = null
        if __LinuxRT.sigaction(LinuxFaultSignals[index], &action, null) != 0 do
            __hostTestAbort()
    }
    linuxTestFilter.installed = 0
    if linuxTestFilter.mapping
    {
        if __LinuxRT.sigaltstack(&linuxTestFilter.previousStack, null) != 0 do
            __hostTestAbort()
        discard __LinuxRT.munmap(linuxTestFilter.mapping, linuxTestFilter.mappingSize)
        linuxTestFilter.mapping = null
    }
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostTestInstallHardwareFilter()->*void
{
    if linuxTestFilter.active do
        __hostTestAbort()
    linuxTestFilter = LinuxTestFilter{}
    const Page = 4096'u64
    let recommended = __LinuxRT.sysconf(250) // _SC_SIGSTKSZ includes extended CPU-state storage.
    let usable = (Swag.max(65536'u64, recommended > 0 ? cast(u64, recommended) : 0) + Page - 1) & ~(Page - 1)
    let size = usable + 2 * Page
    let mapping = __LinuxRT.mmap(null, size, 0, __LinuxRT.MapPrivateAnonymous, -1, 0)
    if cast(s64, mapping) == -1 do
        __hostTestAbort()
    let base = cast(*void, cast(u64, mapping) + Page)
    if __LinuxRT.mprotect(base, usable, __LinuxRT.ProtectReadWrite) != 0
    {
        discard __LinuxRT.munmap(mapping, size)
        __hostTestAbort()
    }
    let stack = __LinuxRT.SignalStack{address: base, size: usable}
    if __LinuxRT.sigaltstack(&stack, &linuxTestFilter.previousStack) != 0
    {
        discard __LinuxRT.munmap(mapping, size)
        __hostTestAbort()
    }
    linuxTestFilter.mapping = mapping
    linuxTestFilter.mappingSize = size
    linuxTestFilter.stackTop = cast(u64, base) + usable - 8
    cast(*u64, linuxTestFilter.stackTop)[] = 0 // End of the recovery stack for unwinding.

    let token = cast(*void, &linuxTestFilter)
    for index in 4'u32
    {
        if __LinuxRT.sigaction(LinuxFaultSignals[index], null, &linuxTestFilter.previous[index]) != 0
        {
            __hostTestRestoreHardwareFilter(token)
            __hostTestAbort()
        }
        var action = linuxTestFilter.previous[index]
        action.handler = cast(*void, &__linuxTestSignal)
        action.flags = LinuxSignalInfo | LinuxSignalOnStack | (action.flags & 0x50000000) // NODEFER, RESTART
        if __LinuxRT.sigaction(LinuxFaultSignals[index], &action, null) != 0
        {
            __hostTestRestoreHardwareFilter(token)
            __hostTestAbort()
        }
        linuxTestFilter.installed += 1
    }
    linuxTestFilter.active = true
    return token
}

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
    if linuxTestFilter.active and __hostCurrentThreadId() == Swag.g_TestThreadId do
        linuxTestFilter.recovering = false
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
