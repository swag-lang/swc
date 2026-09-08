#global if #os == Swag.TargetOs.Windows

#foreignlib("kernel32")
#foreignlib("user32")
#foreignlib("ucrt")

////////////////////////////////////////////////////////////
namespace __Win32RT
{
    alias HANDLE                 = *void?
    alias DWORD                  = u32
    alias SRWLOCK                = *void?
    alias USHORT                 = u16
    alias ULONG                  = u32
    alias ULONG64                = u64
    alias CHAR                   = u8
    alias WCHAR                  = u16
    alias BOOL                   = u8
    alias PFLS_CALLBACK_FUNCTION = func(*void?)
    alias CONDITION_VARIABLE     = *void?
    alias THREAD_START_ROUTINE   = func(*void?)->DWORD
    alias RtlDecompressBufferFn  = func(USHORT, [*] u8, ULONG, const [*] u8, ULONG, *ULONG)->s32

    const STD_OUTPUT_HANDLE       = 0xFFFF_FFF5'u32
    const MB_CANCELTRYCONTINUE    = 0x00000006
    const MB_ICONERROR            = 0x00000010
    const IDCANCEL                = 2
    const IDTRYAGAIN              = 10
    const IDCONTINUE              = 11
    const FALSE: BOOL             = 0
    const TRUE:  BOOL             = 1
    const SRWLOCK_INIT            = cast(SRWLOCK) null
    const CONDITION_VARIABLE_INIT = cast(CONDITION_VARIABLE) null
    const INFINITE                = 0xFFFF_FFFF'u32
    const WAIT_TIMEOUT            = 0x0000_0102'u32
    const ALL_PROCESSOR_GROUPS    = 0x0000_FFFF'u16
    const PAGE_READWRITE_MAP      = 0x0000_0004'u32
    const FILE_MAP_ALL_ACCESS     = 0x000F_001F'u32
    const INVALID_HANDLE          = cast(HANDLE) -1
    const ERROR_ALREADY_EXISTS    = 183'u32
    const MEM_COMMIT              = 0x0000_1000'u32
    const MEM_RESERVE             = 0x0000_2000'u32
    const MEM_DECOMMIT            = 0x0000_4000'u32
    const MEM_RELEASE             = 0x0000_8000'u32
    const PAGE_READWRITE          = 0x0000_0004'u32
    const PAGE_NOACCESS           = 0x0000_0001'u32

    const PF_AVX2_INSTRUCTIONS_AVAILABLE = 40'u32
    const CP_UTF8 = 65001'u32

    #[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
    {
        func RtlCaptureContext(contextRecord: *void)
        func RtlRestoreContext(contextRecord: *void, exceptionRecord: *void?)
        func RtlCaptureStackBackTrace(framesToSkip: ULONG, framesToCapture: ULONG, backTrace: **void, backTraceHash: *ULONG?)->USHORT
        func GetModuleHandleA(lpModuleName: const *u8?)->*void?
        func GetModuleHandleExA(dwFlags: DWORD, lpModuleName: const *u8?, phModule: *(*void?))->BOOL
        func GetProcAddress(hModule: HANDLE, lpProcName: const [*] u8)->const *void?
        func GetCommandLineA()->const [*] u8?
        func GetCommandLineW()->const [*] u16?
        func WideCharToMultiByte(codePage, dwFlags: DWORD, lpWideCharStr: const [*] u16, cchWideChar: s32, lpMultiByteStr: [*] u8?, cbMultiByte: s32, lpDefaultChar: const *u8?, lpUsedDefaultChar: *s32?)->s32
        func GetStdHandle(nStdHandle: u32)->HANDLE
        func WriteFile(hFile: HANDLE, lpBuffer: const *void?, nNumberOfBytesToWrite: u32, lpNumberOfBytesWritten: *u32?, lpOverlapped: *void?)->u32
        func GetCurrentProcess()->HANDLE
        func GetCurrentThreadId()->DWORD
        func SetUnhandledExceptionFilter(lpTopLevelExceptionFilter: *void?)->*void?
        func ExitProcess(uExitCode: u32)
        func RaiseException(dwExceptionCode: u32, dwExceptionFlags: u32, nNumberOfArguments: u32, lpArguments: *const *void)
        func DebugBreak()
        func LoadLibraryA(name: const *u8)->*void?
        func TlsAlloc()->u32
        func TlsSetValue(dwTlsIndex: u32, lpTlsValue: *void?)->BOOL
        func TlsGetValue(dwTlsIndex: u32)->*void?
        func FlsAlloc(lpCallback: PFLS_CALLBACK_FUNCTION?)->u32
        func FlsFree(dwFlsIndex: u32)->BOOL
        func FlsSetValue(dwFlsIndex: u32, lpFlsData: *void?)->BOOL
        func FlsGetValue(dwFlsIndex: u32)->*void?
        func AcquireSRWLockExclusive(SRWLock: *SRWLOCK)
        func ReleaseSRWLockExclusive(SRWLock: *SRWLOCK)
        func VirtualAlloc(lpAddress: *void?, dwSize: ULONG64, flAllocationType: DWORD, flProtect: DWORD)->*void?
        func VirtualFree(lpAddress: *void?, dwSize: ULONG64, dwFreeType: DWORD)->BOOL
        func IsProcessorFeaturePresent(processorFeature: DWORD)->BOOL
        func CreateThread(lpThreadAttributes: *void?, dwStackSize: ULONG64, lpStartAddress: THREAD_START_ROUTINE, lpParameter: *void?, dwCreationFlags: DWORD, lpThreadId: *DWORD?)->HANDLE?
        func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD
        func CloseHandle(hObject: HANDLE)->BOOL
        func SwitchToThread()->BOOL
        func Sleep(dwMilliseconds: DWORD)
        func GetActiveProcessorCount(groupNumber: USHORT)->DWORD
        func QueryPerformanceCounter(counter: *s64)->s32
        func QueryPerformanceFrequency(frequency: *s64)->s32
        func GetCurrentProcessId()->DWORD
        func GetLastError()->DWORD
        func TryAcquireSRWLockExclusive(SRWLock: *SRWLOCK)->BOOL
        func AcquireSRWLockShared(SRWLock: *SRWLOCK)
        func ReleaseSRWLockShared(SRWLock: *SRWLOCK)
        func TryAcquireSRWLockShared(SRWLock: *SRWLOCK)->BOOL
        func InitializeConditionVariable(conditionVariable: *CONDITION_VARIABLE)
        func SleepConditionVariableSRW(conditionVariable: *CONDITION_VARIABLE, SRWLock: *SRWLOCK, dwMilliseconds: DWORD, flags: ULONG)->BOOL
        func WakeConditionVariable(conditionVariable: *CONDITION_VARIABLE)
        func WakeAllConditionVariable(conditionVariable: *CONDITION_VARIABLE)
        func CreateFileMappingW(hFile: HANDLE, lpAttributes: *void?, flProtect: DWORD, dwMaximumSizeHigh: DWORD, dwMaximumSizeLow: DWORD, lpName: const [*] WCHAR?)->HANDLE?
        func MapViewOfFile(hFileMappingObject: HANDLE, dwDesiredAccess: DWORD, dwFileOffsetHigh: DWORD, dwFileOffsetLow: DWORD, dwNumberOfBytesToMap: ULONG64)->*void?
    }

    #[Swag.Foreign("user32", callconv: Swag.CallConv.C)]
    {
        func MessageBoxA(hWnd: const *void?, lpText: const *void, lpCaption: const *void, uType: u32)->s32
    }
}

// Windows implementation of the host primitives used by common allocator and TLS policy.
const AllocatorHostCommitGranularity = 4096'u64

func __hostTlsAlloc()->u64                      => __Win32RT.TlsAlloc()
func __hostTlsGet(id: u64)->*void?              => __Win32RT.TlsGetValue(cast(u32) id)
func __hostTlsSet(id: u64, value: *void?)->bool => __Win32RT.TlsSetValue(cast(u32) id, value) != 0

func __hostThreadStorageAlloc(cleanup: (func(*void?))?)->u64
{
    let slot = __Win32RT.FlsAlloc(cleanup)
    return slot == 0xFFFF_FFFF ? 0 : cast(u64) slot + 1
}

func __hostThreadStorageFree(id: u64)
{
    if id do
        discard __Win32RT.FlsFree(cast(u32) (id - 1))
}

func __hostThreadStorageGet(id: u64)->*void?
{
    return id ? __Win32RT.FlsGetValue(cast(u32) (id - 1)) : null
}

func __hostThreadStorageSet(id: u64, value: *void?)->bool
{
    return id != 0 and __Win32RT.FlsSetValue(cast(u32) (id - 1), value) != 0
}

func __hostCurrentThreadId()->u64 => __Win32RT.GetCurrentThreadId()

////////////////////////////////////////////////////////////
// EXECUTION RESOURCES
////////////////////////////////////////////////////////////

// Starts one host thread running `entry` with `param`, or returns null when the host refuses.
func __hostThreadCreate(entry: func(*void?)->u32, param: *void?)->*void?
{
    return __Win32RT.CreateThread(null, 0, entry, param, 0, null)
}

// Waits for a host thread to finish and releases the handle this runtime owns for it.
func __hostThreadJoin(handle: *void?)
{
    if !handle do
        return
    discard __Win32RT.WaitForSingleObject(handle, __Win32RT.INFINITE)
    discard __Win32RT.CloseHandle(handle)
}

// Yields the remainder of the calling thread's time slice.
func __hostThreadYield()
{
    discard __Win32RT.SwitchToThread()
}

// Suspends the calling thread for at least `milliseconds`.
func __hostThreadSleep(milliseconds: u32)
{
    __Win32RT.Sleep(milliseconds)
}

// Returns how many logical processors the process can run on.
func __hostProcessorCount()->u32
{
    let count = __Win32RT.GetActiveProcessorCount(__Win32RT.ALL_PROCESSOR_GROUPS)
    return count == 0 ? 1 : count
}

// Reads the monotonic host counter without wall-clock adjustments.
func __hostMonotonicTicks()->u64
{
    var counter: s64
    discard __Win32RT.QueryPerformanceCounter(&counter)
    return cast(u64) counter
}

// Returns the number of monotonic host ticks per second.
func __hostMonotonicFrequency()->u64
{
    var frequency: s64
    discard __Win32RT.QueryPerformanceFrequency(&frequency)
    return cast(u64) frequency
}

////////////////////////////////////////////////////////////
// LOCKS AND CONDITIONS
////////////////////////////////////////////////////////////

func __hostLockExclusive(lock: *__Win32RT.SRWLOCK)          => __Win32RT.AcquireSRWLockExclusive(lock)
func __hostUnlockExclusive(lock: *__Win32RT.SRWLOCK)        => __Win32RT.ReleaseSRWLockExclusive(lock)
func __hostTryLockExclusive(lock: *__Win32RT.SRWLOCK)->bool => __Win32RT.TryAcquireSRWLockExclusive(lock) != __Win32RT.FALSE
func __hostLockShared(lock: *__Win32RT.SRWLOCK)             => __Win32RT.AcquireSRWLockShared(lock)
func __hostUnlockShared(lock: *__Win32RT.SRWLOCK)           => __Win32RT.ReleaseSRWLockShared(lock)
func __hostTryLockShared(lock: *__Win32RT.SRWLOCK)->bool    => __Win32RT.TryAcquireSRWLockShared(lock) != __Win32RT.FALSE

func __hostConditionInit(condition: *__Win32RT.CONDITION_VARIABLE)    => __Win32RT.InitializeConditionVariable(condition)
func __hostConditionWake(condition: *__Win32RT.CONDITION_VARIABLE)    => __Win32RT.WakeConditionVariable(condition)
func __hostConditionWakeAll(condition: *__Win32RT.CONDITION_VARIABLE) => __Win32RT.WakeAllConditionVariable(condition)

// Atomically releases `lock`, waits for a wake, and reacquires it. Returns false on timeout.
func __hostConditionWait(condition: *__Win32RT.CONDITION_VARIABLE, lock: *__Win32RT.SRWLOCK, milliseconds: u32)->bool
{
    return __Win32RT.SleepConditionVariableSRW(condition, lock, milliseconds, 0) != __Win32RT.FALSE
}

////////////////////////////////////////////////////////////
// PROCESS-WIDE ANCHOR
////////////////////////////////////////////////////////////

// Publishes `candidate` as the one process-wide value for `key`, and returns the value that
// actually won. Every artifact of one process carries its own copy of the runtime, so a
// scheduler stored in an ordinary global would exist once per executable and per shared
// library. The anchor is a named, process-scoped section: the first artifact to ask installs
// its candidate, and every later artifact -- including one loaded dynamically, and one running
// on a thread the operating system created -- reads back the same pointer.
//
// A host that refuses the section leaves the caller with its own candidate, which stays correct
// for a single-artifact program.
func __hostProcessSingleton(key: u32, candidate: *void)->*void
{
    // "Local\Swag.Rt.<pid>.<key>", built without any allocation or string formatting.
    const Prefix = "Local\\Swag.Rt."
    var name: [64] __Win32RT.WCHAR
    var length = 0'u64

    for c in Prefix
    {
        name[length] = cast(__Win32RT.WCHAR) c
        length       += 1
    }

    __hostAppendHex(&name, &length, __Win32RT.GetCurrentProcessId())
    name[length] = cast(__Win32RT.WCHAR) 46     // '.'
    length       += 1
    __hostAppendHex(&name, &length, key)
    name[length] = 0

    let mapping = __Win32RT.CreateFileMappingW(__Win32RT.INVALID_HANDLE, null, __Win32RT.PAGE_READWRITE_MAP, 0, 8, &name[0])
    if !mapping do
        return candidate

    // The section stays mapped and its handle stays open for the life of the process: it holds
    // the identity every later artifact resolves against.
    let view = __Win32RT.MapViewOfFile(mapping!, __Win32RT.FILE_MAP_ALL_ACCESS, 0, 0, 8)
    if !view do
        return candidate

    let slot     = cast(*u64) view!
    let previous = Swag.atomcmpxchg(slot, 0, cast(u64) candidate)
    return previous == 0 ? candidate : cast(*void) previous
}

private func __hostAppendHex(name: *[64] __Win32RT.WCHAR, length: *u64, value: u32)
{
    const Digits = "0123456789abcdef"
    var shift = 28's32
    var seen  = false

    while shift >= 0
    {
        let digit = (value >> cast(u32) shift) & 0xF
        if digit != 0 or seen or shift == 0
        {
            seen             = true
            name[][length[]] = cast(__Win32RT.WCHAR) Digits[digit]
            length[]         += 1
        }

        shift -= 4
    }
}

func __hostPageReserve(size: u64)->[*] u8?
{
    return cast([*] u8?) __Win32RT.VirtualAlloc(null, size, __Win32RT.MEM_RESERVE, __Win32RT.PAGE_READWRITE)
}

func __hostPageCommit(address: *void?, size: u64)->bool
{
    return __Win32RT.VirtualAlloc(address, size, __Win32RT.MEM_COMMIT, __Win32RT.PAGE_READWRITE) != null
}

func __hostPageDecommit(address: *void?, size: u64)
{
    discard __Win32RT.VirtualFree(address, size, __Win32RT.MEM_DECOMMIT)
}

func __hostPageRelease(address: *void?, _size: u64)
{
    discard __Win32RT.VirtualFree(address, 0, __Win32RT.MEM_RELEASE)
}

////////////////////////////////////////////////////////////
// MUTEX
////////////////////////////////////////////////////////////

#[Swag.NoDoc]
struct MutexRW
{
    v: __Win32RT.SRWLOCK = __Win32RT.SRWLOCK_INIT
}

#[Swag.NoDoc]
impl MutexRW
{
    mtd lock()
    {
        __Win32RT.AcquireSRWLockExclusive(&.v)
    }

    mtd unlock()
    {
        __Win32RT.ReleaseSRWLockExclusive(&.v)
    }
}

////////////////////////////////////////////////////////////
// LIBC
////////////////////////////////////////////////////////////

namespace __Win32RT
{
    #[Swag.Foreign(module: "ucrtbase", link: "ucrt", callconv: Swag.CallConv.C)]
    {
        func sinf(val: f32)->f32
        func cosf(val: f32)->f32
        func tanf(val: f32)->f32
        func sinhf(val: f32)->f32
        func coshf(val: f32)->f32
        func tanhf(val: f32)->f32
        func asinf(val: f32)->f32
        func acosf(val: f32)->f32
        func atanf(val: f32)->f32
        func logf(val: f32)->f32
        func log2f(val: f32)->f32
        func log10f(val: f32)->f32
        func expf(val: f32)->f32
        func exp2f(val: f32)->f32

        func sin(val: f64)->f64
        func cos(val: f64)->f64
        func tan(val: f64)->f64
        func sinh(val: f64)->f64
        func cosh(val: f64)->f64
        func tanh(val: f64)->f64
        func asin(val: f64)->f64
        func acos(val: f64)->f64
        func atan(val: f64)->f64
        func log(val: f64)->f64
        func log2(val: f64)->f64
        func log10(val: f64)->f64
        func exp(val: f64)->f64
        func exp2(val: f64)->f64

        func powf(val1, val2: f32)->f32
        func atan2f(val1, val2: f32)->f32
        func pow(val1, val2: f64)->f64
        func atan2(val1, val2: f64)->f64
    }
}

////////////////////////////////////////////////////////////
// INTRINSIC WRAPPERS
////////////////////////////////////////////////////////////

{
    func sin(value: f32)->f32 => __Win32RT.sinf(value)
    func sin(value: f64)->f64 => __Win32RT.sin(value)
    func cos(value: f32)->f32 => __Win32RT.cosf(value)
    func cos(value: f64)->f64 => __Win32RT.cos(value)
    func tan(value: f32)->f32 => __Win32RT.tanf(value)
    func tan(value: f64)->f64 => __Win32RT.tan(value)

    func sinh(value: f32)->f32 => __Win32RT.sinhf(value)
    func sinh(value: f64)->f64 => __Win32RT.sinh(value)
    func cosh(value: f32)->f32 => __Win32RT.coshf(value)
    func cosh(value: f64)->f64 => __Win32RT.cosh(value)
    func tanh(value: f32)->f32 => __Win32RT.tanhf(value)
    func tanh(value: f64)->f64 => __Win32RT.tanh(value)

    func asin(value: f32)->f32 => __Win32RT.asinf(value)
    func asin(value: f64)->f64 => __Win32RT.asin(value)
    func acos(value: f32)->f32 => __Win32RT.acosf(value)
    func acos(value: f64)->f64 => __Win32RT.acos(value)
    func atan(value: f32)->f32 => __Win32RT.atanf(value)
    func atan(value: f64)->f64 => __Win32RT.atan(value)

    func log(value: f32)->f32   => __Win32RT.logf(value)
    func log(value: f64)->f64   => __Win32RT.log(value)
    func log2(value: f32)->f32  => __Win32RT.log2f(value)
    func log2(value: f64)->f64  => __Win32RT.log2(value)
    func log10(value: f32)->f32 => __Win32RT.log10f(value)
    func log10(value: f64)->f64 => __Win32RT.log10(value)

    func exp(value: f32)->f32  => __Win32RT.expf(value)
    func exp(value: f64)->f64  => __Win32RT.exp(value)
    func exp2(value: f32)->f32 => __Win32RT.exp2f(value)
    func exp2(value: f64)->f64 => __Win32RT.exp2(value)

    func pow(value1, value2: f32)->f32 => __Win32RT.powf(value1, value2)
    func pow(value1, value2: f64)->f64 => __Win32RT.pow(value1, value2)

    func atan2(value1, value2: f32)->f32 => __Win32RT.atan2f(value1, value2)
    func atan2(value1, value2: f64)->f64 => __Win32RT.atan2(value1, value2)
}

////////////////////////////////////////////////////////////
// The command line this process was launched with, still owned by the operating system and
// therefore valid for the whole run. The buffer holds the executable path followed by the
// arguments, which is the shape 'Swag.args()' parses.
func __osCommandLine()->string?
{
    // The system states the command line in both eight-bit and wide forms, and only the wide one
    // carries what the user actually typed: the eight-bit one is folded into the machine's legacy
    // code page, where every character outside it becomes a question mark. A path is then a path
    // that does not exist, which is how a program launched on a file whose name holds an accent
    // opened nothing at all. The conversion below is the only place this run does it, and the
    // buffer it writes into is never released, matching the lifetime the system's own has.
    using __Win32RT
    let wide = GetCommandLineW()
    if wide
    {
        let bytes = WideCharToMultiByte(CP_UTF8, 0, wide!, -1, null, 0, null, null)
        if bytes > 1
        {
            let buffer = cast([*] u8?) VirtualAlloc(null, cast(u64) bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
            if buffer and WideCharToMultiByte(CP_UTF8, 0, wide!, -1, buffer, bytes, null, null) == bytes do
                return Swag.makeString(buffer!, cast(u64) (bytes - 1))
        }
    }

    let cmdLine = GetCommandLineA()
    if !cmdLine do
        return null
    return Swag.makeString(cmdLine!, (cast(const cstring) cmdLine!).count)
}

// Windows answers this only once the operating system has enabled YMM state, which is exactly
// what the VEX-encoded forms the backend emits depend on. A CPUID bit alone would not prove it.
func __hostHasAvx2()->bool => __Win32RT.IsProcessorFeaturePresent(__Win32RT.PF_AVX2_INSTRUCTIONS_AVAILABLE) != __Win32RT.FALSE

////////////////////////////////////////////////////////////
func __printString(message: string?)
{
    if !message or !message.count do
        return
    using __Win32RT
    let len = cast(u32) message.count
    discard WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), message.buffer, len, null, null)
}

////////////////////////////////////////////////////////////
func __raiseException666(message: string?, loc: Swag.SourceCodeLocation, kind: Swag.ExceptionKind)
{
    // In a native binary there is no compiler above us to catch the exception:
    // route the failure through the panic path (which the native #test runner
    // hooks), instead of dying silently on an unhandled SEH exception.
    if !Swag.jit()
    {
        var msg = message
        if !msg
        {
            switch kind
            {
            case .Assert: msg = "assertion does not hold"
            case .Safety: msg = "runtime safety contract does not hold"
            default:      msg = "runtime error"
            }
        }

        Swag.panic(msg, loc)
        return
    }

    let cxt = Swag.getContext()
    cxt.exceptionLoc       = loc
    cxt.exceptionParams[0] = cast(const *void) &cxt.exceptionLoc
    cxt.exceptionParams[1] = cast(const *void?) message.buffer
    cxt.exceptionParams[2] = cast(const *void) cast(u64) message.count
    cxt.exceptionParams[3] = cast(const *void) cast(u64) kind
    __Win32RT.RaiseException(666, 0, 4, &cxt.exceptionParams[0])
}

////////////////////////////////////////////////////////////
func __loaddll(name: string) => __Win32RT.LoadLibraryA(name.buffer)

func __exit()
{
    __Win32RT.ExitProcess(0)
}

////////////////////////////////////////////////////////////
func __exitError()
{
    __Win32RT.ExitProcess(cast #bit (u32) -666)
}

////////////////////////////////////////////////////////////
// Windows context recovery for the common native #test runner. A failed test is abandoned without
// unwinding, matching the process-abort semantics a native panic had before tests could continue.
private var g_TestContextBuf: [1360] u8

private func __hostTestResumeContext()->*void
{
    // RtlCaptureContext/RtlRestoreContext require a 16-byte aligned CONTEXT.
    let addr = cast(u64) &g_TestContextBuf[0]
    return cast(*void) ((addr + 15) & 0xFFFF_FFFF_FFFF_FFF0)
}

func __hostTestResume()
{
    __Win32RT.RtlRestoreContext(__hostTestResumeContext(), null)
}

// Keeps the captured frame alive while a test runs. A panic or hardware fault restores this
// context, then returns through this function to the common runner.
#[Swag.Optimize(false)]
func __hostTestCall(fn: *void)
{
    __Win32RT.RtlCaptureContext(__hostTestResumeContext())
    if g_TestFailed do
        return

    let call = cast(func()) fn
    call()
}

private struct __HostExceptionRecord
{
    code:           u32
    flags:          u32
    nested:         *void?
    address:        *void?
    parameterCount: u32
    padding:        u32
    information:    [15] u64
}

private struct __HostExceptionPointers
{
    record:  *__HostExceptionRecord
    context: *void
}

private func __hostTestUnhandledFilter(exceptionPointers: *void)->s32
{
    if !g_TestRunning or __hostCurrentThreadId() != g_TestThreadId do
        return 0     // EXCEPTION_CONTINUE_SEARCH

    let pointers = cast(const *__HostExceptionPointers) exceptionPointers
    let record   = pointers.record
    var accessKind, accessAddress: u64
    if record.parameterCount >= 2
    {
        accessKind    = record.information[0]
        accessAddress = record.information[1]
    }

    __testHardwareException(record.code, cast(u64) record.address, accessKind, accessAddress)
    return 0
}

func __hostTestInstallHardwareFilter()->*void?
{
    return __Win32RT.SetUnhandledExceptionFilter(cast() &__hostTestUnhandledFilter)
}

func __hostTestRestoreHardwareFilter(previous: *void?)
{
    discard __Win32RT.SetUnhandledExceptionFilter(previous)
}

func __captureStack(skip: u32, wh: [..] (*void?))->u32
{
    using __Win32RT
    let nb = RtlCaptureStackBackTrace(skip + 1, cast() wh.count, cast() wh.buffer, null)
    return nb
}

// Returns the image that owns an address without changing its loader reference count.
func __hostImageBaseForAddress(address: *void)->*void?
{
    var result: *void?
    if __Win32RT.GetModuleHandleExA(6, cast(const *u8) address, &result) == 0 do
        return null
    return result
}

private func __peU16(p: [*] u8, off: u64)->u16 => (&p[off])[as u16]
private func __peU32(p: [*] u8, off: u64)->u32 => (&p[off])[as u32]

// Locates the linker-owned `.swagdbg` payload in one Windows PE image.
func __hostDebugSection(base: *void)->[*] u8?
{
    let image   = cast([*] u8) base
    let ntOff   = cast(u64) __peU32(image, 0x3C)
    let count   = __peU16(image, ntOff + 6)
    let optSize = __peU16(image, ntOff + 20)
    var section = ntOff + 24 + cast(u64) optSize

    let wanted = ".swagdbg"
    for index in count
    {
        var matches = true
        for byte in 8 where image[section + cast(u64) byte] != cast(u8) wanted[byte]
        {
            matches = false
            break
        }

        if matches
        {
            let rva = __peU32(image, section + 12)
            return cast([*] u8) &image[cast(u64) rva]
        }

        section += 40
    }

    return null
}

// Expands the linker-owned version-2 debug table on first use. Version 1 remains a
// direct image view for compatibility with artifacts produced by older compilers.
func __hostDecodeDebugSection(section: [*] u8)->[*] u8?
{
    if __peU32(section, 0) != 0x4244_5753 do
        return null

    let version = __peU32(section, 4)
    if version == 1 do
        return section
    if version != 2 do
        return null

    let decodedSize = __peU32(section, 8)
    let packedSize  = __peU32(section, 12)
    if decodedSize < 16 or packedSize == 0 do
        return null

    let ntdll = __Win32RT.GetModuleHandleA(("ntdll.dll").buffer)
    if !ntdll do
        return null
    let decompressAddress = __Win32RT.GetProcAddress(ntdll, ("RtlDecompressBuffer").buffer)
    if !decompressAddress do
        return null
    let decompress = cast(__Win32RT.RtlDecompressBufferFn) decompressAddress!

    let decoded = cast([*] u8?) __Win32RT.VirtualAlloc(null, decodedSize, __Win32RT.MEM_COMMIT | __Win32RT.MEM_RESERVE, __Win32RT.PAGE_READWRITE)
    if !decoded do
        return null

    var finalSize: u32
    let status = decompress(2, decoded!, decodedSize, &section[16], packedSize, &finalSize)
    if status < 0 or finalSize != decodedSize
    {
        discard __Win32RT.VirtualFree(decoded, 0, __Win32RT.MEM_RELEASE)
        return null
    }

    return decoded
}

func __hostReleaseDecodedDebugSection(section: [*] u8?)
{
    if section do
        discard __Win32RT.VirtualFree(section, 0, __Win32RT.MEM_RELEASE)
}
