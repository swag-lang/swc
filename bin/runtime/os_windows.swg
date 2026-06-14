#global #if #os == Swag.TargetOs.Windows
#foreignlib("kernel32")
#foreignlib("user32")
#foreignlib("ucrt")
#foreignlib("vcruntime")

////////////////////////////////////////////////////////////
namespace __Win32RT
{
    alias HANDLE  = *void
    alias DWORD   = u32
    alias SRWLOCK = *void
    alias USHORT  = u16
    alias ULONG   = u32
    alias ULONG64 = u64
    alias CHAR    = u8
    alias WCHAR   = u16
    alias BOOL    = u8

    const STD_OUTPUT_HANDLE    = 0xFFFF_FFF5'u32
    const MB_CANCELTRYCONTINUE = 0x00000006
    const MB_ICONERROR         = 0x00000010
    const IDCANCEL             = 2
    const IDTRYAGAIN           = 10
    const IDCONTINUE           = 11
    const FALSE:               BOOL = 0
    const TRUE:                BOOL = 1
    const SRWLOCK_INIT         = cast(SRWLOCK) null


    #[Swag.Foreign("kernel32")]
    {
        func RtlCaptureStackBackTrace(framesToSkip: ULONG, framesToCapture: ULONG, backTrace: **void, backTraceHash: #null *ULONG)->USHORT;
        func GetModuleHandleA(lpModuleName: #null const *u8)->*void;
        func GetModuleHandleExA(dwFlags: DWORD, lpModuleName: #null const *u8, phModule: **void)->BOOL;
        func GetStdHandle(nStdHandle: u32)->HANDLE;
        func WriteFile(hFile: HANDLE, lpBuffer: const *void, nNumberOfBytesToWrite: u32, lpNumberOfBytesWritten: #null *u32, lpOverlapped: #null *void)->u32;
        func GetCurrentProcess()->HANDLE;
        func GetCurrentThreadId()->DWORD;
        func ExitProcess(uExitCode: u32);
        func RaiseException(dwExceptionCode: u32, dwExceptionFlags: u32, nNumberOfArguments: u32, lpArguments: *const *void);
        func DebugBreak();
        func LoadLibraryA(name: const *u8);
        func TlsAlloc()->u32;
        func TlsSetValue(dwTlsIndex: u32, lpTlsValue: *void);
        func TlsGetValue(dwTlsIndex: u32)->*void;
        func AcquireSRWLockExclusive(SRWLock: *SRWLOCK);
        func ReleaseSRWLockExclusive(SRWLock: *SRWLOCK);
    }

    #[Swag.Foreign("user32")]
    {
        func MessageBoxA(hWnd: #null const *void, lpText: const *void, lpCaption: const *void, uType: u32)->s32;
    }
}

////////////////////////////////////////////////////////////
// MUTEX
////////////////////////////////////////////////////////////

#[Swag.NoDoc]
struct MutexRW
{
    v:   __Win32RT.SRWLOCK = __Win32RT.SRWLOCK_INIT
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

#[Swag.Foreign(module: "ucrtbase", link: "ucrt")]
{
    func sinf(val: f32)->f32;
    func cosf(val: f32)->f32;
    func tanf(val: f32)->f32;
    func sinhf(val: f32)->f32;
    func coshf(val: f32)->f32;
    func tanhf(val: f32)->f32;
    func asinf(val: f32)->f32;
    func acosf(val: f32)->f32;
    func atanf(val: f32)->f32;
    func logf(val: f32)->f32;
    func log2f(val: f32)->f32;
    func log10f(val: f32)->f32;
    func floorf(val: f32)->f32;
    func ceilf(val: f32)->f32;
    func truncf(val: f32)->f32;
    func roundf(val: f32)->f32;
    func expf(val: f32)->f32;
    func exp2f(val: f32)->f32;
    func sqrtf(val: f32)->f32;

    func sin(val: f64)->f64;
    func cos(val: f64)->f64;
    func tan(val: f64)->f64;
    func sinh(val: f64)->f64;
    func cosh(val: f64)->f64;
    func tanh(val: f64)->f64;
    func asin(val: f64)->f64;
    func acos(val: f64)->f64;
    func atan(val: f64)->f64;
    func log(val: f64)->f64;
    func log2(val: f64)->f64;
    func log10(val: f64)->f64;
    func floor(val: f64)->f64;
    func ceil(val: f64)->f64;
    func trunc(val: f64)->f64;
    func round(val: f64)->f64;
    func exp(val: f64)->f64;
    func exp2(val: f64)->f64;
    func sqrt(val: f64)->f64;

    func powf(val1, val2: f32)->f32;
    func atan2f(val1, val2: f32)->f32;
    func pow(val1, val2: f64)->f64;
    func atan2(val1, val2: f64)->f64;

    func malloc(s: s64)->[*] void;
    func realloc(ptr: [*] void, s: s64)->[*] void;
    func free(ptr: [*] void);
    func memcpy(dst: [*] void, src: const [*] void, size: s64)->[*] void;
    func memmove(dst: [*] void, src: const [*] void, size: s64)->[*] void;
    func memset(dst: [*] void, value: s32, size: s64)->[*] void;
    func memcmp(dst, src: const [*] void, size: s64)->s32;
}

////////////////////////////////////////////////////////////
// INTRINSIC WRAPPERS
////////////////////////////////////////////////////////////

func @alloc(size: u64)->[*] void
{
    return malloc(cast(s64) size)
}

func @realloc(ptr: [*] void, size: u64)->[*] void
{
    return realloc(ptr, cast(s64) size)
}

func @free(ptr: [*] void)
{
    free(ptr)
}

func @memset(dst: [*] void, value: u8, size: u64)
{
    discard memset(dst, cast(s32) value, cast(s64) size)
}

func @memcpy(dst: [*] void, src: const [*] void, size: u64)
{
    discard memcpy(dst, src, cast(s64) size)
}

func @memmove(dst: [*] void, src: const [*] void, size: u64)
{
    discard memmove(dst, src, cast(s64) size)
}

func @memcmp(dst, src: const [*] void, size: u64)->s32
{
    return memcmp(dst, src, cast(s64) size)
}

{
    func @sin(value: f32)->f32  => sinf(value)
    func @sin(value: f64)->f64  => sin(value)
    func @cos(value: f32)->f32  => cosf(value)
    func @cos(value: f64)->f64  => cos(value)
    func @tan(value: f32)->f32  => tanf(value)
    func @tan(value: f64)->f64  => tan(value)

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

    func @floor(value: f32)->f32 => floorf(value)
    func @floor(value: f64)->f64 => floor(value)
    func @ceil(value: f32)->f32  => ceilf(value)
    func @ceil(value: f64)->f64  => ceil(value)
    func @trunc(value: f32)->f32 => truncf(value)
    func @trunc(value: f64)->f64 => trunc(value)
    func @round(value: f32)->f32 => roundf(value)
    func @round(value: f64)->f64 => round(value)
    func @sqrt(value: f32)->f32  => sqrtf(value)
    func @sqrt(value: f64)->f64  => sqrt(value)

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
func __printString(message: string)
{
    if !@dataof(message) or !@countof(message) do
        return
    using __Win32RT
    let len = cast(u32) @countof(message)
    discard WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), @dataof(message), len, null, null)
}

////////////////////////////////////////////////////////////
func __raiseException666(message: string, loc: Swag.SourceCodeLocation, kind: Swag.ExceptionKind)
{
    let cxt = @getcontext()
    cxt.exceptionLoc       = loc
    cxt.exceptionParams[0] = cast(const *void) &cxt.exceptionLoc
    cxt.exceptionParams[1] = cast(const *void) @dataof(message)
    cxt.exceptionParams[2] = cast(const *void) cast(u64) @countof(message)
    cxt.exceptionParams[3] = cast(const *void) cast(u64) kind
    __Win32RT.RaiseException(666, 0, 4, &cxt.exceptionParams[0])
}

////////////////////////////////////////////////////////////
func __loaddll(name: string)              => __Win32RT.LoadLibraryA(@dataof(name))

func __exit()
{
    __Win32RT.ExitProcess(0)
}

func __tlsAlloc()                         => cast(u64) __Win32RT.TlsAlloc()
func __tlsSetValue(id: u64, value: *void) => __Win32RT.TlsSetValue(cast(u32) id, value)
func __tlsGetValue(id: u64)->*void        => __Win32RT.TlsGetValue(cast(u32) id)

////////////////////////////////////////////////////////////
func __tlsGetPtr(id: u64, size: u64, init: const *void)->*void
{
    using __Win32RT
    var ptr = TlsGetValue(cast(u32) id)
    if ptr do
        return ptr
    ptr = @alloc(size)
    @memcpy(ptr, init, size)
    TlsSetValue(cast(u32) id, ptr)
    return ptr
}

////////////////////////////////////////////////////////////
func __exitError()
{
    __Win32RT.ExitProcess(cast #bit (u32) -666)
}

func __panicBox(msg, title: string)
{
    using __Win32RT
    let result = MessageBoxA(null, @dataof(msg), @dataof(title), MB_ICONERROR | MB_CANCELTRYCONTINUE)
    switch result
    {
    case IDCANCEL:
        __exitError()
    case IDTRYAGAIN:
        DebugBreak()
    case IDCONTINUE:
        break
    }
}

func __captureStack(skip: u32, wh: [..] *void)->u32
{
    using __Win32RT
    let nb = RtlCaptureStackBackTrace(skip + 1, cast() @countof(wh), cast() @dataof(wh), null)
    return nb
}

// Self-symbolization. The linker embeds a `.swagdbg` section in every image (a per-function table of
// name + source file/line keyed by image-relative address); the runtime reads it directly, so stack
// traces need neither a PDB nor dbghelp. A one-entry cache avoids re-parsing the PE for consecutive
// frames in the same module.
struct __SwagSym
{
    found:   bool   = false
    hasLine: bool   = false
    name:    string = ""
    file:    string = ""
    line:    u32    = 0
}

var __dbgCacheBase:    *void  = null
var __dbgCacheSection: [*] u8 = null
var __dbgCacheCount:   u32    = 0
var __dbgCacheValid:   bool   = false

func __peU16(p: [*] u8, off: u64)->u16 => dref cast(*u16) &p[off]
func __peU32(p: [*] u8, off: u64)->u32 => dref cast(*u32) &p[off]

func __dbgFindSection(base: *void)
{
    __dbgCacheBase    = base
    __dbgCacheValid   = false
    __dbgCacheSection = null
    __dbgCacheCount   = 0
    if base == null do
        return

    let b      = cast([*] u8) base
    let ntOff  = cast(u64) __peU32(b, 0x3C)
    let nSec   = __peU16(b, ntOff + 6)
    let optSz  = __peU16(b, ntOff + 20)
    var secOff = ntOff + 24 + cast(u64) optSz

    let want = ".swagdbg"
    for s in nSec
    {
        var match = true
        for k in 8
        {
            if b[secOff + cast(u64) k] != cast(u8) want[k]
            {
                match = false
                break
            }
        }

        if match
        {
            let rva           = __peU32(b, secOff + 12)
            __dbgCacheSection = cast([*] u8) &b[cast(u64) rva]
            __dbgCacheCount   = __peU32(__dbgCacheSection, 8)
            __dbgCacheValid   = true
            return
        }
        secOff += 40
    }
}

func __dbgStr(off: u32)->string
{
    if off == 0 do
        return ""
    let p = cast([*] u8) &__dbgCacheSection[cast(u64) off]
    return @mkstring(p, @countof(cast(cstring) p))
}

func __symbolize(addr: *void)->__SwagSym
{
    using __Win32RT
    var r: __SwagSym

    // GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS(4) | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT(2)
    var h: *void = null
    if GetModuleHandleExA(6, cast(const *u8) addr, &h) == 0 do
        return r
    if h != __dbgCacheBase do
        __dbgFindSection(h)
    if !__dbgCacheValid do
        return r

    let rva = cast(u32) (cast(u64) addr - cast(u64) h)
    let sec = __dbgCacheSection
    for i in __dbgCacheCount
    {
        let e     = 16 + cast(u64) i * 20
        let erva  = __peU32(sec, e)
        let esize = __peU32(sec, e + 4)
        if rva >= erva and rva < erva + esize
        {
            r.found = true
            r.name  = __dbgStr(__peU32(sec, e + 8))
            let fileOff = __peU32(sec, e + 12)
            if fileOff != 0
            {
                r.hasLine = true
                r.file    = __dbgStr(fileOff)
                r.line    = __peU32(sec, e + 16)
            }
            return r
        }
    }
    return r
}

func __logStackTrace(wh: [..] *void, startAfter: *Swag.SourceCodeLocation = null, printNoLine = true)
{
    var hasStarted = false

    for i in wh
    {
        let info = __symbolize(wh[i])
        if !info.hasLine and !printNoLine do
            continue

        // Do not print the call until a given location has been reached.
        if !hasStarted and startAfter
        {
            if !info.hasLine do
                continue
            if startAfter.lineStart + 1 != info.line do
                continue
            if @countof(info.file) != @countof(startAfter.fileName) do
                continue

            var samePath = true
            for it in @countof(info.file)
            {
                if info.file[it] == startAfter.fileName[it] do
                    continue
                if info.file[it] == '\\' and startAfter.fileName[it] == '/' do
                    continue
                if info.file[it] == '/' and startAfter.fileName[it] == '\\' do
                    continue
                samePath = false
                break
            }

            if !samePath do
                continue
            hasStarted = true
            continue
        }

        hasStarted = true

        if info.found do
            @print(info.name)

        if info.hasLine
        {
            @print(" --> ")
            @print(info.file, ":", info.line)
        }

        @print("\n")
    }
}
