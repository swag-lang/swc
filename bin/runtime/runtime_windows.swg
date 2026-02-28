#global #if #os == Swag.TargetOs.Windows
#foreignlib("kernel32")
#foreignlib("user32")
#foreignlib("dbghelp")
#foreignlib("ucrt")

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

    struct SYMBOL_INFO
    {
        SizeOfStruct:     ULONG
        TypeIndex:        ULONG           // Type Index of symbol
        Reserved:         [2] ULONG64
        Index:            ULONG
        Size:             ULONG
        ModBase:          ULONG64         // Base Address of module comtaining this symbol
        Flags:            ULONG
        Value:            ULONG64         // Value of symbol, ValuePresent should be 1
        Address:          ULONG64         // Address of symbol including base address of module
        Register:         ULONG           // register holding value or pointer to value
        Scope:            ULONG           // scope of the symbol
        Tag:              ULONG           // pdb classification
        NameLen:          ULONG           // Actual length of name
        MaxNameLen:       ULONG
        Name:             [1] CHAR        // Name of symbol
    }

    struct SYMBOL_INFOW
    {
        SizeOfStruct:     ULONG
        TypeIndex:        ULONG           // Type Index of symbol
        Reserved:         [2] ULONG64
        Index:            ULONG
        Size:             ULONG
        ModBase:          ULONG64         // Base Address of module comtaining this symbol
        Flags:            ULONG
        Value:            ULONG64         // Value of symbol, ValuePresent should be 1
        Address:          ULONG64         // Address of symbol including base address of module
        Register:         ULONG           // register holding value or pointer to value
        Scope:            ULONG           // scope of the symbol
        Tag:              ULONG           // pdb classification
        NameLen:          ULONG           // Actual length of name
        MaxNameLen:       ULONG
        Name:             [1] WCHAR       // Name of symbol
    }

    struct IMAGEHLP_LINE64
    {
        SizeOfStruct:     DWORD        // set to sizeof(IMAGEHLP_LINE64)
        Key:              *void        // fileprivate
        LineNumber:       DWORD        // line number in file
        FileName:         [*] CHAR     // full filename
        Address:          ULONG64      // first instruction of line
    }

    struct IMAGEHLP_LINEW64
    {
        SizeOfStruct:     DWORD         // set to sizeof(IMAGEHLP_LINEW64)
        Key:              *void         // fileprivate
        LineNumber:       DWORD         // line number in file
        FileName:         [*] WCHAR     // full filename
        Address:          ULONG64       // first instruction of line
    }

    #[Swag.Foreign("DbgHelp")]
    {
        func SymInitialize(hProcess: HANDLE, userSearchPath: #null *CHAR, fInvadeProcess: BOOL)->BOOL;
        func SymCleanup(hProcess: HANDLE)->BOOL;
        func SymFromAddr(hProcess: HANDLE, address: ULONG64, displacement: *ULONG64, symbol: *SYMBOL_INFO)->BOOL;
        func SymFromAddrW(hProcess: HANDLE, address: ULONG64, displacement: *ULONG64, symbol: *SYMBOL_INFOW)->BOOL;
        func SymGetLineFromAddr64(hProcess: HANDLE, dwAddr: ULONG64, pdwDisplacement: *DWORD, line: *IMAGEHLP_LINE64)->BOOL;
        func SymGetLineFromAddrW64(hProcess: HANDLE, dwAddr: ULONG64, pdwDisplacement: *DWORD, line: *IMAGEHLP_LINEW64)->BOOL;
    }

    #[Swag.Foreign("kernel32")]
    {
        func RtlCaptureStackBackTrace(framesToSkip: ULONG, framesToCapture: ULONG, backTrace: **void, backTraceHash: #null *ULONG)->USHORT;
        func GetStdHandle(nStdHandle: u32)->HANDLE;
        func WriteFile(hFile: HANDLE, lpBuffer: const *void, nNumberOfBytesToWrite: u32, lpNumberOfBytesWritten: #null *u32, lpOverlapped: #null *void)->u32;
        func GetCurrentProcess()->HANDLE;
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

#[Swag.Foreign("ucrtbase")]
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

#[Swag.Overload]
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
func __exit()                             => __Win32RT.ExitProcess(0)
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

var __logStackTraceInitDone = false
func __logStackTrace(wh: [..] *void, startAfter: *Swag.SourceCodeLocation = null, printNoLine = true)
{
    using __Win32RT

    if !__logStackTraceInitDone
    {
        if !SymInitialize(GetCurrentProcess(), null, TRUE) do
            return
        __logStackTraceInitDone = true
    }

    const SYM_LEN_NAME = 128
    var sym:           [#sizeof(SYMBOL_INFO) + SYM_LEN_NAME * #sizeof(CHAR)] u8
    var displacement:  ULONG64

    let psym = cast(*SYMBOL_INFO) sym
    psym.SizeOfStruct = #sizeof(SYMBOL_INFO)
    psym.MaxNameLen   = SYM_LEN_NAME

    var line: IMAGEHLP_LINE64
    line.SizeOfStruct = #sizeof(IMAGEHLP_LINE64)

    var hasStarted = false

    for i in wh
    {
        let hasSymbol = SymFromAddr(GetCurrentProcess(), cast(ULONG64) cast(u64) wh[i], &displacement, psym)
        let hasLine   = SymGetLineFromAddr64(GetCurrentProcess(), cast(ULONG64) cast(u64) wh[i], cast() &displacement, &line)
        let fileName  = hasLine ? @mkstring(line.FileName, @countof(cast(cstring) line.FileName)) : null
        if !hasLine and !printNoLine do
            continue

        // Do not print the call until a given location has been reached.
        // For DebugAllocator leaks
        if !hasStarted and startAfter
        {
            if !hasLine or !fileName do
                continue
            if startAfter.lineStart + 1 != line.LineNumber do
                continue
            if @countof(fileName) != @countof(startAfter.fileName) do
                continue

            var samePath = true
            for it in @countof(fileName)
            {
                if fileName[it] == startAfter.fileName[it] do
                    continue
                if fileName[it] == '\\' and startAfter.fileName[it] == '/' do
                    continue
                if fileName[it] == '/' and startAfter.fileName[it] == '\\' do
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

        if hasSymbol
        {
            let symName = @mkstring(cast(const [*] u8) psym.Name, @countof(cast(cstring) psym.Name))
            @print(symName)
        }

        if hasLine
        {
            @print(" --> ")
            @print(fileName, ":", line.LineNumber)
        }

        @print("\n")
    }
}
