#global if #os == Swag.TargetOs.Windows

#foreignlib("kernel32")
#foreignlib("user32")
#foreignlib("ucrt")

////////////////////////////////////////////////////////////
namespace __Win32RT
{
    alias HANDLE                 = #null *void
    alias DWORD                  = u32
    alias SRWLOCK                = #null *void
    alias USHORT                 = u16
    alias ULONG                  = u32
    alias ULONG64                = u64
    alias CHAR                   = u8
    alias WCHAR                  = u16
    alias BOOL                   = u8
    alias PFLS_CALLBACK_FUNCTION = func(#null *void)

    const STD_OUTPUT_HANDLE    = 0xFFFF_FFF5'u32
    const MB_CANCELTRYCONTINUE = 0x00000006
    const MB_ICONERROR         = 0x00000010
    const IDCANCEL             = 2
    const IDTRYAGAIN           = 10
    const IDCONTINUE           = 11
    const FALSE: BOOL          = 0
    const TRUE:  BOOL          = 1
    const SRWLOCK_INIT         = cast(SRWLOCK) null
    const MEM_COMMIT           = 0x0000_1000'u32
    const MEM_RESERVE          = 0x0000_2000'u32
    const MEM_DECOMMIT         = 0x0000_4000'u32
    const MEM_RELEASE          = 0x0000_8000'u32
    const PAGE_READWRITE       = 0x0000_0004'u32
    const PAGE_NOACCESS        = 0x0000_0001'u32

    const PF_AVX2_INSTRUCTIONS_AVAILABLE = 40'u32

    #[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
    {
        func RtlCaptureContext(contextRecord: *void)
        func RtlRestoreContext(contextRecord: *void, exceptionRecord: #null *void)
        func RtlCaptureStackBackTrace(framesToSkip: ULONG, framesToCapture: ULONG, backTrace: **void, backTraceHash: #null *ULONG)->USHORT
        func GetModuleHandleA(lpModuleName: #null const *u8)->#null *void
        func GetModuleHandleExA(dwFlags: DWORD, lpModuleName: #null const *u8, phModule: *#null *void)->BOOL
        func GetCommandLineA()->#null const [*] u8
        func GetStdHandle(nStdHandle: u32)->HANDLE
        func WriteFile(hFile: HANDLE, lpBuffer: #null const *void, nNumberOfBytesToWrite: u32, lpNumberOfBytesWritten: #null *u32, lpOverlapped: #null *void)->u32
        func GetCurrentProcess()->HANDLE
        func GetCurrentThreadId()->DWORD
        func SetUnhandledExceptionFilter(lpTopLevelExceptionFilter: #null *void)->#null *void
        func ExitProcess(uExitCode: u32)
        func RaiseException(dwExceptionCode: u32, dwExceptionFlags: u32, nNumberOfArguments: u32, lpArguments: *const *void)
        func DebugBreak()
        func LoadLibraryA(name: const *u8)->#null *void
        func TlsAlloc()->u32
        func TlsSetValue(dwTlsIndex: u32, lpTlsValue: #null *void)->BOOL
        func TlsGetValue(dwTlsIndex: u32)->#null *void
        func FlsAlloc(lpCallback: #null PFLS_CALLBACK_FUNCTION)->u32
        func FlsFree(dwFlsIndex: u32)->BOOL
        func FlsSetValue(dwFlsIndex: u32, lpFlsData: #null *void)->BOOL
        func FlsGetValue(dwFlsIndex: u32)->#null *void
        func AcquireSRWLockExclusive(SRWLock: *SRWLOCK)
        func ReleaseSRWLockExclusive(SRWLock: *SRWLOCK)
        func VirtualAlloc(lpAddress: #null *void, dwSize: ULONG64, flAllocationType: DWORD, flProtect: DWORD)->#null *void
        func VirtualFree(lpAddress: #null *void, dwSize: ULONG64, dwFreeType: DWORD)->BOOL
        func IsProcessorFeaturePresent(processorFeature: DWORD)->BOOL
    }

    #[Swag.Foreign("user32", callconv: Swag.CallConv.C)]
    {
        func MessageBoxA(hWnd: #null const *void, lpText: const *void, lpCaption: const *void, uType: u32)->s32
    }
}

// Windows implementation of the host primitives used by common allocator and TLS policy.
const AllocatorHostCommitGranularity = 4096'u64

func __hostTlsAlloc()->u64                           => __Win32RT.TlsAlloc()
func __hostTlsGet(id: u64)->#null *void              => __Win32RT.TlsGetValue(cast(u32) id)
func __hostTlsSet(id: u64, value: #null *void)->bool => __Win32RT.TlsSetValue(cast(u32) id, value) != 0

func __hostThreadStorageAlloc(cleanup: #null func(#null *void))->u64
{
    let slot = __Win32RT.FlsAlloc(cleanup)
    return slot == 0xFFFF_FFFF ? 0 : cast(u64) slot + 1
}

func __hostThreadStorageFree(id: u64)
{
    if id do
        discard __Win32RT.FlsFree(cast(u32) (id - 1))
}

func __hostThreadStorageGet(id: u64)->#null *void
{
    return id ? __Win32RT.FlsGetValue(cast(u32) (id - 1)) : null
}

func __hostThreadStorageSet(id: u64, value: #null *void)->bool
{
    return id != 0 and __Win32RT.FlsSetValue(cast(u32) (id - 1), value) != 0
}

func __hostCurrentThreadId()->u64 => __Win32RT.GetCurrentThreadId()

func __hostPageReserve(size: u64)->#null [*] u8
{
    return cast(#null [*] u8) __Win32RT.VirtualAlloc(null, size, __Win32RT.MEM_RESERVE, __Win32RT.PAGE_READWRITE)
}

func __hostPageCommit(address: #null *void, size: u64)->bool
{
    return __Win32RT.VirtualAlloc(address, size, __Win32RT.MEM_COMMIT, __Win32RT.PAGE_READWRITE) != null
}

func __hostPageDecommit(address: #null *void, size: u64)
{
    discard __Win32RT.VirtualFree(address, size, __Win32RT.MEM_DECOMMIT)
}

func __hostPageRelease(address: #null *void, _size: u64)
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

////////////////////////////////////////////////////////////
// INTRINSIC WRAPPERS
////////////////////////////////////////////////////////////

{
    func @sin(value: f32)->f32 => sinf(value)
    func @sin(value: f64)->f64 => sin(value)
    func @cos(value: f32)->f32 => cosf(value)
    func @cos(value: f64)->f64 => cos(value)
    func @tan(value: f32)->f32 => tanf(value)
    func @tan(value: f64)->f64 => tan(value)

    func @sinh(value: f32)->f32 => sinhf(value)
    func @sinh(value: f64)->f64 => sinh(value)
    func @cosh(value: f32)->f32 => coshf(value)
    func @cosh(value: f64)->f64 => cosh(value)
    func @tanh(value: f32)->f32 => tanhf(value)
    func @tanh(value: f64)->f64 => tanh(value)

    func @asin(value: f32)->f32 => asinf(value)
    func @asin(value: f64)->f64 => asin(value)
    func @acos(value: f32)->f32 => acosf(value)
    func @acos(value: f64)->f64 => acos(value)
    func @atan(value: f32)->f32 => atanf(value)
    func @atan(value: f64)->f64 => atan(value)

    func @log(value: f32)->f32   => logf(value)
    func @log(value: f64)->f64   => log(value)
    func @log2(value: f32)->f32  => log2f(value)
    func @log2(value: f64)->f64  => log2(value)
    func @log10(value: f32)->f32 => log10f(value)
    func @log10(value: f64)->f64 => log10(value)

    func @exp(value: f32)->f32  => expf(value)
    func @exp(value: f64)->f64  => exp(value)
    func @exp2(value: f32)->f32 => exp2f(value)
    func @exp2(value: f64)->f64 => exp2(value)

    func @pow(value1, value2: f32)->f32 => powf(value1, value2)
    func @pow(value1, value2: f64)->f64 => pow(value1, value2)

    func @atan2(value1, value2: f32)->f32 => atan2f(value1, value2)
    func @atan2(value1, value2: f64)->f64 => atan2(value1, value2)
}

////////////////////////////////////////////////////////////
// The command line this process was launched with, still owned by the operating system and
// therefore valid for the whole run. The buffer holds the executable path followed by the
// arguments, which is the shape '@args' parses.
func __osCommandLine()->#null string
{
    let cmdLine = __Win32RT.GetCommandLineA()
    if !cmdLine do
        return null
    return @mkstring(cmdLine!, @countof(cast(const cstring) cmdLine!))
}

// Windows answers this only once the operating system has enabled YMM state, which is exactly
// what the VEX-encoded forms the backend emits depend on. A CPUID bit alone would not prove it.
func __hostHasAvx2()->bool => __Win32RT.IsProcessorFeaturePresent(__Win32RT.PF_AVX2_INSTRUCTIONS_AVAILABLE) != __Win32RT.FALSE

////////////////////////////////////////////////////////////
func __printString(message: #null string)
{
    if !message or !@countof(message) do
        return
    using __Win32RT
    let len = cast(u32) @countof(message)
    discard WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), @dataof(message), len, null, null)
}

////////////////////////////////////////////////////////////
func __raiseException666(message: #null string, loc: Swag.SourceCodeLocation, kind: Swag.ExceptionKind)
{
    // In a native binary there is no compiler above us to catch the exception:
    // route the failure through the panic path (which the native #test runner
    // hooks), instead of dying silently on an unhandled SEH exception.
    if !@jit
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

        @panic(msg, loc)
        return
    }

    let cxt = @getcontext()
    cxt.exceptionLoc       = loc
    cxt.exceptionParams[0] = cast(const *void) &cxt.exceptionLoc
    cxt.exceptionParams[1] = cast(#null const *void) @dataof(message)
    cxt.exceptionParams[2] = cast(const *void) cast(u64) @countof(message)
    cxt.exceptionParams[3] = cast(const *void) cast(u64) kind
    __Win32RT.RaiseException(666, 0, 4, &cxt.exceptionParams[0])
}

////////////////////////////////////////////////////////////
func __loaddll(name: string) => __Win32RT.LoadLibraryA(@dataof(name))

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
    nested:         #null *void
    address:        #null *void
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

func __hostTestInstallHardwareFilter()->#null *void
{
    return __Win32RT.SetUnhandledExceptionFilter(cast() &__hostTestUnhandledFilter)
}

func __hostTestRestoreHardwareFilter(previous: #null *void)
{
    discard __Win32RT.SetUnhandledExceptionFilter(previous)
}

func __captureStack(skip: u32, wh: [..] *void)->u32
{
    using __Win32RT
    let nb = RtlCaptureStackBackTrace(skip + 1, cast() @countof(wh), cast() @dataof(wh), null)
    return nb
}

// Returns the image that owns an address without changing its loader reference count.
func __hostImageBaseForAddress(address: *void)->#null *void
{
    var result: #null *void
    if __Win32RT.GetModuleHandleExA(6, cast(const *u8) address, &result) == 0 do
        return null
    return result
}

private func __peU16(p: [*] u8, off: u64)->u16 => (&p[off])[as u16]
private func __peU32(p: [*] u8, off: u64)->u32 => (&p[off])[as u32]

// Locates the linker-owned `.swagdbg` payload in one Windows PE image.
func __hostDebugSection(base: *void)->#null [*] u8
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
