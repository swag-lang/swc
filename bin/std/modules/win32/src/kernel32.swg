#global export

#foreignlib("kernel32")
using Swag

alias ATOM                   = u16
alias HANDLE                 = #null const [*] void
alias HGLOBAL                = HANDLE
alias HLOCAL                 = HANDLE
alias HINSTANCE              = HANDLE
alias HMODULE                = HANDLE
alias LRESULT                = s64
alias WORD                   = u16
alias DWORD                  = u32
alias BOOL                   = s32
alias BOOLEAN                = u8
alias BYTE                   = u8
alias LPBYTE                 = #null *BYTE
alias LONG                   = s32
alias ULONG                  = u32
alias LPVOID                 = #null [*] void
alias LPCVOID                = #null const [*] void
alias LPCSTR                 = #null const [*] u8
alias PCSTR                  = #null const [*] u8
alias LPCWSTR                = #null const [*] u16
alias PCWSTR                 = #null const [*] u16
alias LPCTSTR                = #null const [*] u16
alias LPDWORD                = #null *DWORD
alias DWORD_PTR              = u64
alias ULONG_PTR              = u64
alias UINT                   = u32
alias INT                    = s32
alias SHORT                  = s16
alias USHORT                 = u16
alias LARGE_INTEGER          = s64
alias ULARGE_INTEGER         = u64
alias DWORD64                = u64
alias ULONG64                = u64
alias PLONG                  = #null *LONG
alias LONG_PTR               = s64
alias CHAR                   = u8
alias WCHAR                  = u16
alias LPSTR                  = #null [*] CHAR
alias LPWSTR                 = #null [*] WCHAR
alias LPCH                   = #null [*] CHAR
alias LPWCH                  = #null [*] WCHAR
alias SIZE_T                 = u64
alias va_list                = #null [*] u8

alias LPTHREAD_START_ROUTINE = func(#null *void)->DWORD
alias WAITORTIMERCALLBACK    = func(#null *void, BOOL)

const STD_INPUT_HANDLE      = cast #bit (DWORD) -10
const STD_OUTPUT_HANDLE     = cast #bit (DWORD) -11
const STD_ERROR_HANDLE      = cast #bit (DWORD) -12
const ATTACH_PARENT_PROCESS = cast #bit (DWORD) -1

const FALSE = 0
const TRUE  = 1

const FOREGROUND_BLUE      = 0x0001
const FOREGROUND_GREEN     = 0x0002
const FOREGROUND_RED       = 0x0004
const FOREGROUND_INTENSITY = 0x0008
const FOREGROUND_MASK      = 0x000F
const BACKGROUND_BLUE      = 0x0010
const BACKGROUND_GREEN     = 0x0020
const BACKGROUND_RED       = 0x0040
const BACKGROUND_INTENSITY = 0x0080
const BACKGROUND_MASK      = 0x00F0

const FILE_SHARE_READ   = 0x00000001
const FILE_SHARE_WRITE  = 0x00000002
const FILE_SHARE_DELETE = 0x00000004

const FILE_ATTRIBUTE_READONLY              = 0x00000001
const FILE_ATTRIBUTE_HIDDEN                = 0x00000002
const FILE_ATTRIBUTE_SYSTEM                = 0x00000004
const FILE_ATTRIBUTE_DIRECTORY             = 0x00000010
const FILE_ATTRIBUTE_ARCHIVE               = 0x00000020
const FILE_ATTRIBUTE_DEVICE                = 0x00000040
const FILE_ATTRIBUTE_NORMAL                = 0x00000080
const FILE_ATTRIBUTE_TEMPORARY             = 0x00000100
const FILE_ATTRIBUTE_SPARSE_FILE           = 0x00000200
const FILE_ATTRIBUTE_REPARSE_POINT         = 0x00000400
const FILE_ATTRIBUTE_COMPRESSED            = 0x00000800
const FILE_ATTRIBUTE_OFFLINE               = 0x00001000
const FILE_ATTRIBUTE_NOT_CONTENT_INDEXED   = 0x00002000
const FILE_ATTRIBUTE_ENCRYPTED             = 0x00004000
const FILE_ATTRIBUTE_INTEGRITY_STREAM      = 0x00008000
const FILE_ATTRIBUTE_VIRTUAL               = 0x00010000
const FILE_ATTRIBUTE_NO_SCRUB_DATA         = 0x00020000
const FILE_ATTRIBUTE_EA                    = 0x00040000
const FILE_ATTRIBUTE_PINNED                = 0x00080000
const FILE_ATTRIBUTE_UNPINNED              = 0x00100000
const FILE_ATTRIBUTE_RECALL_ON_OPEN        = 0x00040000
const FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = 0x00400000

const GENERIC_READ          = 0x80000000
const GENERIC_WRITE         = 0x40000000
const GENERIC_EXECUTE       = 0x20000000
const GENERIC_ALL           = 0x10000000
const FILE_READ_ATTRIBUTES  = 0x0080
const FILE_WRITE_ATTRIBUTES = 0x0100
const FILE_LIST_DIRECTORY   = 0x0001

const FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
const FILE_FLAG_OVERLAPPED       = 0x40000000

const PAGE_READONLY  = 0x02
const PAGE_READWRITE = 0x04
const PAGE_WRITECOPY = 0x08

const FILE_MAP_COPY  = 0x0001
const FILE_MAP_WRITE = 0x0002
const FILE_MAP_READ  = 0x0004

const FILE_NOTIFY_CHANGE_FILE_NAME   = 0x00000001
const FILE_NOTIFY_CHANGE_DIR_NAME    = 0x00000002
const FILE_NOTIFY_CHANGE_ATTRIBUTES  = 0x00000004
const FILE_NOTIFY_CHANGE_SIZE        = 0x00000008
const FILE_NOTIFY_CHANGE_LAST_WRITE  = 0x00000010
const FILE_NOTIFY_CHANGE_LAST_ACCESS = 0x00000020
const FILE_NOTIFY_CHANGE_CREATION    = 0x00000040
const FILE_NOTIFY_CHANGE_SECURITY    = 0x00000100

const FILE_ACTION_ADDED            = 0x00000001
const FILE_ACTION_REMOVED          = 0x00000002
const FILE_ACTION_MODIFIED         = 0x00000003
const FILE_ACTION_RENAMED_OLD_NAME = 0x00000004
const FILE_ACTION_RENAMED_NEW_NAME = 0x00000005

const FILE_BEGIN               = 0'u32
const FILE_CURRENT             = 1'u32
const FILE_END                 = 2'u32
const INVALID_FILE_SIZE        = cast #bit (DWORD) -1
const INVALID_SET_FILE_POINTER = cast #bit (DWORD) -1
const INVALID_FILE_ATTRIBUTES  = cast #bit (DWORD) -1

const CREATE_NEW        = 1'u32
const CREATE_ALWAYS     = 2'u32
const OPEN_EXISTING     = 3'u32
const OPEN_ALWAYS       = 4'u32
const TRUNCATE_EXISTING = 5'u32

const INVALID_HANDLE_VALUE    = cast(HANDLE) cast #bit (u64) -1's64
const CONSOLE_TEXTMODE_BUFFER = 1'u32
const MAX_PATH                = 260
const LOCALE_NAME_MAX_LENGTH  = 85
const INFINITE                = 0xFFFFFFFF
const CREATE_SUSPENDED        = 0x00000004
const MAXIMUM_WAIT_OBJECTS    = 64'u32

const CREATE_UNICODE_ENVIRONMENT = 0x00000400

const STARTF_USESHOWWINDOW = 0x00000001
const STARTF_USESTDHANDLES = 0x00000100

const MOVEFILE_REPLACE_EXISTING = 0x00000001
const MOVEFILE_COPY_ALLOWED     = 0x00000002

const HANDLE_FLAG_INHERIT            = 0x00000001
const HANDLE_FLAG_PROTECT_FROM_CLOSE = 0x00000002
const DUPLICATE_SAME_ACCESS          = 0x00000002

const FORMAT_MESSAGE_ALLOCATE_BUFFER = 0x00000100
const FORMAT_MESSAGE_IGNORE_INSERTS  = 0x00000200
const FORMAT_MESSAGE_FROM_STRING     = 0x00000400
const FORMAT_MESSAGE_FROM_HMODULE    = 0x00000800
const FORMAT_MESSAGE_FROM_SYSTEM     = 0x00001000
const FORMAT_MESSAGE_ARGUMENT_ARRAY  = 0x00002000
const FORMAT_MESSAGE_MAX_WIDTH_MASK  = 0x000000FF

const LANG_ENGLISH    = 0x09
const SUBLANG_DEFAULT = 0x01
func MAKELANGID(p, s: WORD) => (s << 10) | p

const WAIT_OBJECT_0  = 0x00000000
const WAIT_ABANDONED = 0x00000080
const WAIT_TIMEOUT   = 0x00000102
const WAIT_FAILED    = 0xFFFFFFFF

const THREAD_PRIORITY_LOWEST       = -2
const THREAD_PRIORITY_BELOW_NORMAL = -1
const THREAD_PRIORITY_NORMAL       = 0
const THREAD_PRIORITY_ABOVE_NORMAL = 1
const THREAD_PRIORITY_HIGHEST      = 2
const THREAD_PRIORITY_ERROR_RETURN = 0x7FFFFFFF

func LOWORD(l: u64) => cast(u32) (l & 0xFFFF)
func HIWORD(l: u64) => cast(u32) ((l >> 16) & 0xFFFF)

alias SRWLOCK = #null *void
const SRWLOCK_INIT = cast(SRWLOCK) null

const GMEM_FIXED          = 0x0000
const GMEM_MOVEABLE       = 0x0002
const GMEM_NOCOMPACT      = 0x0010
const GMEM_NODISCARD      = 0x0020
const GMEM_ZEROINIT       = 0x0040
const GMEM_MODIFY         = 0x0080
const GMEM_DISCARDABLE    = 0x0100
const GMEM_NOT_BANKED     = 0x1000
const GMEM_SHARE          = 0x2000
const GMEM_DDESHARE       = 0x2000
const GMEM_NOTIFY         = 0x4000
const GMEM_LOWER          = GMEM_NOT_BANKED
const GMEM_VALID_FLAGS    = 0x7F72
const GMEM_INVALID_HANDLE = 0x8000

struct COORD
{
    public
    {
        x: WORD
        y: WORD
    }
}

struct POINT
{
    public
    {
        x: LONG
        y: LONG
    }
}

struct SMALL_RECT
{
    public
    {
        left:   WORD
        top:    WORD
        right:  WORD
        bottom: WORD
    }
}

struct CONSOLE_SCREEN_BUFFER_INFO
{
    public
    {
        dwSize:              COORD
        dwCursorPosition:    COORD
        wAttributes:         WORD
        srWindow:            SMALL_RECT
        dwMaximumWindowSize: COORD
    }
}

struct SYSTEM_INFO
{
    public
    {
        dwOemId:                     DWORD     // Must be updated to an union
        dwPageSize:                  DWORD
        lpMinimumApplicationAddress: LPVOID
        lpMaximumApplicationAddress: LPVOID
        dwActiveProcessorMask:       DWORD_PTR
        dwNumberOfProcessors:        DWORD
        dwProcessorType:             DWORD
        dwAllocationGranularity:     DWORD
        wProcessorLevel:             WORD
        wProcessorRevision:          WORD
    }
}

struct SYSTEMTIME
{
    public
    {
        wYear:         WORD
        wMonth:        WORD
        wDayOfWeek:    WORD
        wDay:          WORD
        wHour:         WORD
        wMinute:       WORD
        wSecond:       WORD
        wMilliseconds: WORD
    }
}

struct SECURITY_ATTRIBUTES
{
    public
    {
        nLength:              DWORD
        lpSecurityDescriptor: LPVOID
        bInheritHandle:       BOOL
    }
}

struct OVERLAPPED_OFFSET
{
    public
    {
        Offset:     DWORD
        OffsetHigh: DWORD
    }
}

struct OVERLAPPED
{
    public
    {
        Internal:     ULONG_PTR
        InternalHigh: ULONG_PTR
        using data:   union
        {
            fileOffset: OVERLAPPED_OFFSET
            Pointer:    #null *void
        }
        hEvent: HANDLE
    }
}

struct FILE_NOTIFY_INFORMATION
{
    public
    {
        NextEntryOffset: DWORD
        Action:          DWORD
        FileNameLength:  DWORD
        FileName:        [1] WCHAR
    }
}

alias LPOVERLAPPED = #null *OVERLAPPED
alias LPOVERLAPPED_COMPLETION_ROUTINE = func(DWORD, DWORD, LPOVERLAPPED)

#assert(#sizeof(ATOM) == 2)
#assert(#sizeof(LONG_PTR) == 8)
#assert(#sizeof(OVERLAPPED) == 32)

struct FILETIME
{
    public
    {
        dwLowDateTime:  DWORD
        dwHighDateTime: DWORD
    }
}

struct WIN32_FILE_ATTRIBUTE_DATA
{
    public
    {
        dwFileAttributes: DWORD
        ftCreationTime:   FILETIME
        ftLastAccessTime: FILETIME
        ftLastWriteTime:  FILETIME
        nFileSizeHigh:    DWORD
        nFileSizeLow:     DWORD
    }
}

struct WIN32_FIND_DATAA
{
    public
    {
        dwFileAttributes:   DWORD
        ftCreationTime:     FILETIME
        ftLastAccessTime:   FILETIME
        ftLastWriteTime:    FILETIME
        nFileSizeHigh:      DWORD
        nFileSizeLow:       DWORD
        dwReserved0:        DWORD
        dwReserved1:        DWORD
        cFileName:          [MAX_PATH] CHAR
        cAlternateFileName: [14] CHAR
        dwFileType:         DWORD
        dwCreatorType:      DWORD
        wFinderFlags:       WORD
    }
}

struct WIN32_FIND_DATAW
{
    public
    {
        dwFileAttributes:   DWORD
        ftCreationTime:     FILETIME
        ftLastAccessTime:   FILETIME
        ftLastWriteTime:    FILETIME
        nFileSizeHigh:      DWORD
        nFileSizeLow:       DWORD
        dwReserved0:        DWORD
        dwReserved1:        DWORD
        cFileName:          [MAX_PATH] WCHAR
        cAlternateFileName: [14] WCHAR
        dwFileType:         DWORD
        dwCreatorType:      DWORD
        wFinderFlags:       WORD
    }
}

enum GET_FILEEX_INFO_LEVELS
{
    GetFileExInfoStandard
    GetFileExMaxInfoLevel
}

struct STARTUPINFOA
{
    public
    {
        cb:              DWORD
        lpReserved:      LPSTR
        lpDesktop:       LPSTR
        lpTitle:         LPSTR
        dwX:             DWORD
        dwY:             DWORD
        dwXSize:         DWORD
        dwYSize:         DWORD
        dwXCountChars:   DWORD
        dwYCountChars:   DWORD
        dwFillAttribute: DWORD
        dwFlags:         DWORD
        wShowWindow:     WORD
        cbReserved2:     WORD
        lpReserved2:     LPBYTE
        hStdInput:       HANDLE
        hStdOutput:      HANDLE
        hStdError:       HANDLE
    }
}

struct STARTUPINFOW
{
    public
    {
        cb:              DWORD
        lpReserved:      LPWSTR
        lpDesktop:       LPWSTR
        lpTitle:         LPWSTR
        dwX:             DWORD
        dwY:             DWORD
        dwXSize:         DWORD
        dwYSize:         DWORD
        dwXCountChars:   DWORD
        dwYCountChars:   DWORD
        dwFillAttribute: DWORD
        dwFlags:         DWORD
        wShowWindow:     WORD
        cbReserved2:     WORD
        lpReserved2:     LPBYTE
        hStdInput:       HANDLE
        hStdOutput:      HANDLE
        hStdError:       HANDLE
    }
}

struct PROCESS_INFORMATION
{
    public
    {
        hProcess:    HANDLE
        hThread:     HANDLE
        dwProcessId: DWORD
        dwThreadId:  DWORD
    }
}

const JobObjectBasicAccountingInformation = 1'u32
const JobObjectExtendedLimitInformation   = 9'u32

struct IO_COUNTERS
{
    public
    {
        ReadOperationCount:  u64
        WriteOperationCount: u64
        OtherOperationCount: u64
        ReadTransferCount:   u64
        WriteTransferCount:  u64
        OtherTransferCount:  u64
    }
}

struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION
{
    public
    {
        TotalUserTime:             LARGE_INTEGER
        TotalKernelTime:           LARGE_INTEGER
        ThisPeriodTotalUserTime:   LARGE_INTEGER
        ThisPeriodTotalKernelTime: LARGE_INTEGER
        TotalPageFaultCount:       DWORD
        TotalProcesses:            DWORD
        ActiveProcesses:           DWORD
        TotalTerminatedProcesses:  DWORD
    }
}

struct JOBOBJECT_BASIC_LIMIT_INFORMATION
{
    public
    {
        PerProcessUserTimeLimit: LARGE_INTEGER
        PerJobUserTimeLimit:     LARGE_INTEGER
        LimitFlags:              DWORD
        MinimumWorkingSetSize:   SIZE_T
        MaximumWorkingSetSize:   SIZE_T
        ActiveProcessLimit:      DWORD
        Affinity:                ULONG_PTR
        PriorityClass:           DWORD
        SchedulingClass:         DWORD
    }
}

struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
{
    public
    {
        BasicLimitInformation: JOBOBJECT_BASIC_LIMIT_INFORMATION
        IoInfo:                IO_COUNTERS
        ProcessMemoryLimit:    SIZE_T
        JobMemoryLimit:        SIZE_T
        PeakProcessMemoryUsed: SIZE_T
        PeakJobMemoryUsed:     SIZE_T
    }
}

enum FINDEX_INFO_LEVELS
{
    FindExInfoStandard
    FindExInfoBasic
    FindExInfoMaxInfoLevel
}

enum FINDEX_SEARCH_OPS
{
    FindExSearchNameMatch
    FindExSearchLimitToDirectories
    FindExSearchLimitToDevices
    FindExSearchMaxSearchOp
}

const FIND_FIRST_EX_CASE_SENSITIVE       = 1
const FIND_FIRST_EX_LARGE_FETCH          = 2
const FIND_FIRST_EX_ON_DISK_ENTRIES_ONLY = 4

#[Foreign("kernel32", callconv: Swag.CallConv.C), Discardable]
{
    func SwitchToThread()->BOOL
}

#[Foreign("kernel32", callconv: Swag.CallConv.C)]
{
    func VirtualUnlock(lpAddress: LPVOID, dwSize: SIZE_T)->BOOL
    func GetLastError()->DWORD
    func FormatMessageA(dwFlags: DWORD, lpSource: LPCVOID, dwMessageId: DWORD, dwLanguageId: DWORD, lpBuffer: LPCSTR, nSize: DWORD, Arguments: #null *va_list)->DWORD
    func IsDebuggerPresent()->BOOL
    func DebugBreak()
    func OutputDebugStringA(lpOutputString: LPCSTR)
    func OutputDebugStringW(lpOutputString: LPCWSTR)
    func DebugActiveProcess(procId: DWORD)
    func GetCommandLineA()->#null const [*] u8
    func GetCommandLineW()->#null const [*] u16
    func GetEnvironmentStringsW()->#null [*] WCHAR
    func FreeEnvironmentStringsW(penv: #null [*] WCHAR)->BOOL
    func GetEnvironmentVariableW(lpName: LPCWSTR, lpBuffer: #null LPWSTR, nSize: DWORD)->DWORD

    func GetProcAddress(hModule: HMODULE, lpProcName: LPCSTR)->#null const *void
    func GetCurrentProcess()->HANDLE
    func GetCurrentProcessId()->DWORD
    func GetModuleFileNameW(hModule: HMODULE, lpFilename: LPWSTR, nSize: DWORD)->DWORD
    func GetModuleHandleA(lpModuleName: LPCSTR)->HMODULE
    func GetModuleHandleW(lpModuleName: LPCWSTR)->HMODULE
    func GetStdHandle(nStdHandle: DWORD)->HANDLE
    func CreateConsoleScreenBuffer(dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: #null const *SECURITY_ATTRIBUTES, dwFlags: DWORD, lpScreenBufferData: LPVOID)->HANDLE
    func SetConsoleActiveScreenBuffer(hConsoleOutput: HANDLE)
    func WriteConsoleOutputCharacterA(hConsoleOutput: HANDLE, lpCharacter: LPCSTR, nLength: DWORD, dwWriteCoord: DWORD, lpNumberOfCharsWritten: LPDWORD)->BOOL
    func WriteConsoleOutputCharacterW(hConsoleOutput: HANDLE, lpCharacter: LPCTSTR, nLength: DWORD, dwWriteCoord: DWORD, lpNumberOfCharsWritten: LPDWORD)->BOOL
    func SetConsoleOutputCP(codePage: UINT)
    func GetLogicalDrives()->DWORD
    func GetLogicalDriveStringsA(nBufferLength: DWORD, lpBuffer: LPCSTR)->DWORD
    func GetLogicalDriveStringsW(nBufferLength: DWORD, lpBuffer: LPWSTR)->DWORD

    func GetSystemInfo(lpSystemInfo: *SYSTEM_INFO)
    func GlobalAlloc(uFlags: UINT, dwBytes: SIZE_T)->HGLOBAL
    func GlobalFree(hMem: HGLOBAL)->HGLOBAL
    func LocalFree(hLocal: HLOCAL)->HLOCAL
    func GlobalLock(hMem: HGLOBAL)->LPVOID
    func GlobalUnlock(hMem: HGLOBAL)->BOOL
    func GlobalSize(hMem: HGLOBAL)->SIZE_T

    func QueryPerformanceCounter(lpPerformanceCount: *LARGE_INTEGER)
    func QueryPerformanceFrequency(lpFrequency: *LARGE_INTEGER)
    func GetLocalTime(lpSystemTime: *SYSTEMTIME)
    func GetSystemTime(lpSystemTime: *SYSTEMTIME)

    func Sleep(dwMilliseconds: DWORD)
    func SleepEx(dwMilliseconds: DWORD, bAltertable: BOOL)
    func ExitProcess(uExitCode: UINT)
    func GetCurrentThreadId()->DWORD
    func GetCurrentThread()->HANDLE

    func AcquireSRWLockExclusive(SRWLock: *SRWLOCK)
    func AcquireSRWLockShared(SRWLock: *SRWLOCK)
    func InitializeSRWLock(SRWLock: *SRWLOCK)
    func ReleaseSRWLockExclusive(SRWLock: *SRWLOCK)
    func ReleaseSRWLockShared(SRWLock: *SRWLOCK)
    func TryAcquireSRWLockExclusive(SRWLock: *SRWLOCK)->BOOL
    func TryAcquireSRWLockShared(SRWLock: *SRWLOCK)->BOOL

    func CreateWaitableTimerA(lpTimerAttributes: #null *SECURITY_ATTRIBUTES, bManualReset: BOOL, lpTimerName: LPCSTR)->HANDLE
    func CreateWaitableTimerW(lpTimerAttributes: #null *SECURITY_ATTRIBUTES, bManualReset: BOOL, lpTimerName: LPCWSTR)->HANDLE
    func CancelWaitableTimer(hTimer: HANDLE)->BOOL
    func SetWaitableTimer(hTimer: HANDLE, lpDueTime: const *LARGE_INTEGER, lPeriod: LONG, pfnCompletionRoutine: #null *void, lpArgToCompletionRoutine: LPVOID, fResume: BOOL)->BOOL

    func ReadFile(hFile: HANDLE, lpBuffer: LPVOID, nNumberOfBytesToRead: DWORD, lpNumberOfBytesRead: LPDWORD, lpOverlapped: LPOVERLAPPED)->BOOL
    func PeekNamedPipe(hNamedPipe: HANDLE, lpBuffer: #null LPVOID, nBufferSize: DWORD, lpBytesRead: #null LPDWORD, lpTotalBytesAvail: #null LPDWORD, lpBytesLeftThisMessage: #null LPDWORD)->BOOL
    func CloseHandle(handle: HANDLE)
    func RtlZeroMemory(destination: LPVOID, length: SIZE_T)->LPVOID
    func FileTimeToLocalFileTime(lpFileTime: const *FILETIME, lpLocalFileTime: *FILETIME)->BOOL
}

internal namespace Win32Priv
{
    #[Foreign("kernel32", callconv: Swag.CallConv.C)]
    {
        func AllocConsole()->BOOL
        func FreeConsole()->BOOL
        func AttachConsole(dwProcessId: DWORD)->BOOL
        func SetConsoleTextAttribute(hConsoleOutput: HANDLE, wAttributes: WORD)->BOOL
        func GetConsoleScreenBufferInfo(hConsoleOutput: HANDLE, lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO)->BOOL

        func CreateThread(lpThreadAttributes: #null *SECURITY_ATTRIBUTES, dwStackSize: SIZE_T, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE
        func GetThreadPriority(hThread: HANDLE)->s32
        func ResumeThread(hThread: HANDLE)->DWORD
        func SetThreadPriority(hThread: HANDLE, nPriority: s32)->BOOL
        func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD
        func WaitForMultipleObjects(nCount: DWORD, lpHandles: const *HANDLE, bWaitAll: BOOL, dwMilliseconds: DWORD)->DWORD
        func ReleaseMutex(hMutex: HANDLE)->BOOL
        func ResetEvent(hEvent: HANDLE)->BOOL
        func SetEvent(hEvent: HANDLE)->BOOL

        func CreateJobObjectW(lpJobAttributes: #null *SECURITY_ATTRIBUTES, lpName: #null LPCWSTR)->HANDLE
        func AssignProcessToJobObject(hJob: HANDLE, hProcess: HANDLE)->BOOL
        func QueryInformationJobObject(hJob: HANDLE, JobObjectInformationClass: DWORD, lpJobObjectInformation: LPVOID, cbJobObjectInformationLength: DWORD, lpReturnLength: #null *DWORD)->BOOL
        func SetProcessAffinityMask(hProcess: HANDLE, dwProcessAffinityMask: ULONG_PTR)->BOOL

        func CreateProcessA(lpApplicationName: LPCSTR, lpCommandLine: LPCSTR, lpProcessAttributes: #null *SECURITY_ATTRIBUTES, lpThreadAttributes: #null *SECURITY_ATTRIBUTES, bInheritHandles: BOOL, dwCreationFlags: DWORD, lpEnvironment: LPVOID, lpCurrentDirectory: LPCSTR, lpStartupInfo: *STARTUPINFOA, lpProcessInformation: *PROCESS_INFORMATION)->BOOL
        func CreateProcessW(lpApplicationName: LPCWSTR, lpCommandLine: LPCWSTR, lpProcessAttributes: #null *SECURITY_ATTRIBUTES, lpThreadAttributes: #null *SECURITY_ATTRIBUTES, bInheritHandles: BOOL, dwCreationFlags: DWORD, lpEnvironment: LPVOID, lpCurrentDirectory: LPCWSTR, lpStartupInfo: *STARTUPINFOW, lpProcessInformation: *PROCESS_INFORMATION)->BOOL
        func GetExitCodeProcess(hProcess: HANDLE, lpExitCode: LPDWORD)->BOOL
        func TerminateProcess(hProcess: HANDLE, uExitCode: UINT)->BOOL
        func CreatePipe(hReadPipe: *HANDLE, hWritePipe: *HANDLE, lpPipeAttributes: #null const *SECURITY_ATTRIBUTES, nSize: DWORD)->BOOL
        func SetHandleInformation(hObject: HANDLE, dwMask: DWORD, dwFlags: DWORD)->BOOL
        func CreateEventA(lpEventAttributes: #null *SECURITY_ATTRIBUTES, bManualReset: BOOL, bInitialState: BOOL, lpName: LPCSTR)->HANDLE
        func CreateEventW(lpEventAttributes: #null *SECURITY_ATTRIBUTES, bManualReset: BOOL, bInitialState: BOOL, lpName: LPCWSTR)->HANDLE
        func CreateMutexA(lpMutexAttributes: #null *SECURITY_ATTRIBUTES, bInitialOwner: BOOL, lpName: LPCSTR)->HANDLE
        func CreateMutexW(lpMutexAttributes: #null *SECURITY_ATTRIBUTES, bInitialOwner: BOOL, lpName: LPCWSTR)->HANDLE
        func CreateTimerQueueTimer(phNewTimer: *HANDLE, timerQueue: HANDLE, callback: WAITORTIMERCALLBACK, parameter: #null *void, dueTime: DWORD, period: DWORD, flags: ULONG)->BOOL
        func DeleteTimerQueueTimer(timerQueue: HANDLE, timer: HANDLE, completionEvent: HANDLE)->BOOL

        func WriteFile(hFile: HANDLE, lpBuffer: LPCVOID, nNumberOfBytesToWrite: DWORD, lpNumberOfBytesWritten: LPDWORD, lpOverlapped: LPOVERLAPPED)->BOOL
        func DeleteFileA(lpFileName: LPCSTR)->BOOL
        func MoveFileExW(lpExistingFileName: LPCWSTR, lpNewFileName: #null LPCWSTR, dwFlags: DWORD)->BOOL
        func DeleteFileW(lpFileName: LPCWSTR)->BOOL
        func GetFileAttributesA(lpFileName: LPCSTR)->DWORD
        func GetFileAttributesW(lpFileName: LPCWSTR)->DWORD
        func GetFileAttributesExA(lpFileName: LPCSTR, fInfoLevelId: GET_FILEEX_INFO_LEVELS, lpFileInformation: LPVOID)->BOOL
        func GetFileAttributesExW(lpFileName: LPCWSTR, fInfoLevelId: GET_FILEEX_INFO_LEVELS, lpFileInformation: LPVOID)->BOOL
        func CreateFileA(lpFileName: LPCSTR, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: #null *SECURITY_ATTRIBUTES, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: HANDLE)->HANDLE
        func CreateFileW(lpFileName: LPCWSTR, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: #null *SECURITY_ATTRIBUTES, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: HANDLE)->HANDLE
        func SetFilePointer(hFile: HANDLE, lDistanceToMove: LONG, lpDistanceToMoveHigh: PLONG, dwMoveMethod: DWORD)->DWORD
        func SetFilePointerEx(hFile: HANDLE, liDistanceToMove: LARGE_INTEGER, lpNewFilePointer: #null *LARGE_INTEGER, dwMoveMethod: DWORD)->BOOL
        func GetFileSize(hFile: HANDLE, lpFileSizeHigh: LPDWORD)->DWORD
        func GetFileSizeEx(hFile: HANDLE, lpFileSize: *LARGE_INTEGER)->BOOL
        func SetEndOfFile(hFile: HANDLE)->BOOL
        func FlushFileBuffers(hFile: HANDLE)->BOOL
        func CreateFileMappingW(hFile: HANDLE, lpFileMappingAttributes: #null *SECURITY_ATTRIBUTES, flProtect: DWORD, dwMaximumSizeHigh: DWORD, dwMaximumSizeLow: DWORD, lpName: LPCWSTR)->HANDLE
        func MapViewOfFile(hFileMappingObject: HANDLE, dwDesiredAccess: DWORD, dwFileOffsetHigh: DWORD, dwFileOffsetLow: DWORD, dwNumberOfBytesToMap: SIZE_T)->LPVOID
        func UnmapViewOfFile(lpBaseAddress: LPCVOID)->BOOL
        func FlushViewOfFile(lpBaseAddress: LPCVOID, dwNumberOfBytesToFlush: SIZE_T)->BOOL
        func DuplicateHandle(hSourceProcessHandle: HANDLE, hSourceHandle: HANDLE, hTargetProcessHandle: HANDLE, lpTargetHandle: *HANDLE, dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwOptions: DWORD)->BOOL
        func ReadDirectoryChangesW(hDirectory: HANDLE, lpBuffer: LPVOID, nBufferLength: DWORD, bWatchSubtree: BOOL, dwNotifyFilter: DWORD, lpBytesReturned: LPDWORD, lpOverlapped: LPOVERLAPPED, lpCompletionRoutine: #null LPOVERLAPPED_COMPLETION_ROUTINE)->BOOL
        func GetOverlappedResult(hFile: HANDLE, lpOverlapped: *OVERLAPPED, lpNumberOfBytesTransferred: *DWORD, bWait: BOOL)->BOOL
        func CancelIoEx(hFile: HANDLE, lpOverlapped: LPOVERLAPPED)->BOOL

        func FileTimeToSystemTime(lpFileTime: const *FILETIME, lpSystemTime: *SYSTEMTIME)->BOOL
        func SystemTimeToFileTime(lpSystemTime: const *SYSTEMTIME, lpFileTime: *FILETIME)->BOOL
        func SetFileTime(hFile: HANDLE, lpCreationTime: #null const *FILETIME, lpLastAccessTime: #null const *FILETIME, lpLastWriteTime: #null const *FILETIME)->BOOL

        func FindFirstFileA(lpFileName: LPCSTR, lpFindFileData: *WIN32_FIND_DATAA)->HANDLE
        func FindFirstFileW(lpFileName: LPCWSTR, lpFindFileData: *WIN32_FIND_DATAW)->HANDLE
        func FindFirstFileExA(lpFileName: LPCSTR, fInfoLevelId: FINDEX_INFO_LEVELS, lpFindFileData: LPVOID, fSearchOp: FINDEX_SEARCH_OPS, lpSearchFilter: LPVOID, dwAdditionalFlags: DWORD)->HANDLE
        func FindFirstFileExW(lpFileName: LPCWSTR, fInfoLevelId: FINDEX_INFO_LEVELS, lpFindFileData: LPVOID, fSearchOp: FINDEX_SEARCH_OPS, lpSearchFilter: LPVOID, dwAdditionalFlags: DWORD)->HANDLE
        func FindNextFileA(hFindFile: HANDLE, lpFindFileData: *WIN32_FIND_DATAA)->BOOL
        func FindNextFileW(hFindFile: HANDLE, lpFindFileData: *WIN32_FIND_DATAW)->BOOL
        func FindClose(hFindFile: HANDLE)->BOOL
        func FindFirstVolumeA(lpszVolumeName: LPSTR, cchBufferLength: DWORD)->HANDLE
        func FindFirstVolumeW(lpszVolumeName: LPWSTR, cchBufferLength: DWORD)->HANDLE
        func FindNextVolumeA(hFindVolume: HANDLE, lpszVolumeName: LPSTR, cchBufferLength: DWORD)->BOOL
        func FindNextVolumeW(hFindVolume: HANDLE, lpszVolumeName: LPWSTR, cchBufferLength: DWORD)->BOOL
        func FindVolumeClose(hFindVolume: HANDLE)->BOOL
        func GetVolumePathNamesForVolumeNameA(lpszVolumeName: LPCSTR, lpszVolumePathNames: LPCH, cchBufferLength: DWORD, lpcchReturnLength: *DWORD)->BOOL
        func GetVolumePathNamesForVolumeNameW(lpszVolumeName: LPCWSTR, lpszVolumePathNames: LPWCH, cchBufferLength: DWORD, lpcchReturnLength: *DWORD)->BOOL

        func CreateDirectoryA(lpPathName: LPCSTR, lpSecurityAttributes: #null *SECURITY_ATTRIBUTES)->BOOL
        func CreateDirectoryW(lpPathName: LPCWSTR, lpSecurityAttributes: #null *SECURITY_ATTRIBUTES)->BOOL
        func RemoveDirectoryA(lpPathName: LPCSTR)->BOOL
        func RemoveDirectoryW(lpPathName: LPCWSTR)->BOOL
        func GetCurrentDirectoryA(nBufferLength: DWORD, lpBuffer: LPCSTR)->DWORD
        func GetCurrentDirectoryW(nBufferLength: DWORD, lpBuffer: LPCWSTR)->DWORD
        func GetTempPathA(nBufferLength: DWORD, lpBuffer: LPSTR)->DWORD
        func GetTempPathW(nBufferLength: DWORD, lpBuffer: LPWSTR)->DWORD
        func SetCurrentDirectoryA(lpPathName: LPCSTR)->BOOL
        func SetCurrentDirectoryW(lpPathName: LPCWSTR)->BOOL
        func GetFullPathNameA(lpFileName: LPCSTR, nBufferLength: DWORD, lpBuffer: LPSTR, lpFilePart: #null *LPSTR)->DWORD
        func GetFullPathNameW(lpFileName: LPCTSTR, nBufferLength: DWORD, lpBuffer: LPWSTR, lpFilePart: #null *LPWSTR)->DWORD
        func GetUserDefaultLocaleName(lpLocaleName: LPWSTR, cchLocaleName: s32)->s32
    }
}

#[Inline]
{
    func AllocConsole() fail
    {
        if !Win32Priv.AllocConsole() do
            failWinError(GetLastError())
    }

    func FreeConsole() fail
    {
        if !Win32Priv.FreeConsole() do
            failWinError(GetLastError())
    }

    func AttachConsole(dwProcessId: DWORD) fail
    {
        if !Win32Priv.AttachConsole(dwProcessId) do
            failWinError(GetLastError())
    }

    func SetConsoleTextAttribute(hConsoleOutput: HANDLE, wAttributes: WORD) fail
    {
        if !Win32Priv.SetConsoleTextAttribute(hConsoleOutput, wAttributes) do
            failWinError(GetLastError())
    }

    func GetConsoleScreenBufferInfo(hConsoleOutput: HANDLE, lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO) fail
    {
        if !Win32Priv.GetConsoleScreenBufferInfo(hConsoleOutput, lpConsoleScreenBufferInfo) do
            failWinError(GetLastError())
    }

    func CreateThread(lpThreadAttributes: #null *SECURITY_ATTRIBUTES, dwStackSize: SIZE_T, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE fail
    {
        let h = Win32Priv.CreateThread(lpThreadAttributes, dwStackSize, lpStartAddress, lpParameter, dwCreationFlags, lpThreadId)
        if h == null do
            failWinError(GetLastError())
        return h
    }

    func GetThreadPriority(hThread: HANDLE)->s32 fail
    {
        let result = Win32Priv.GetThreadPriority(hThread)
        if result == THREAD_PRIORITY_ERROR_RETURN do
            failWinError(GetLastError())
        return result
    }

    #[Discardable]
    func ResumeThread(hThread: HANDLE)->DWORD fail
    {
        let res = Win32Priv.ResumeThread(hThread)
        if res == cast #bit (DWORD) -1 do
            failWinError(GetLastError())
        return res
    }

    func SetThreadPriority(hThread: HANDLE, nPriority: s32) fail
    {
        if !Win32Priv.SetThreadPriority(hThread, nPriority) do
            failWinError(GetLastError())
    }

    #[Discardable]
    func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD fail
    {
        let res = Win32Priv.WaitForSingleObject(hHandle, dwMilliseconds)
        if res == WAIT_FAILED do
            failWinError(GetLastError())
        return res
    }

    #[Discardable]
    func WaitForMultipleObjects(nCount: DWORD, lpHandles: const *HANDLE, bWaitAll: BOOL, dwMilliseconds: DWORD)->DWORD fail
    {
        let res = Win32Priv.WaitForMultipleObjects(nCount, lpHandles, bWaitAll, dwMilliseconds)
        if res == WAIT_FAILED do
            failWinError(GetLastError())
        return res
    }

    func ReleaseMutex(hMutex: HANDLE) fail
    {
        if !Win32Priv.ReleaseMutex(hMutex) do
            failWinError(GetLastError())
    }

    func ResetEvent(hEvent: HANDLE) fail
    {
        if !Win32Priv.ResetEvent(hEvent) do
            failWinError(GetLastError())
    }

    func SetEvent(hEvent: HANDLE) fail
    {
        if !Win32Priv.SetEvent(hEvent) do
            failWinError(GetLastError())
    }

    func CreateProcessA(lpApplicationName: LPCSTR, lpCommandLine: LPCSTR, lpProcessAttributes: #null *SECURITY_ATTRIBUTES, lpThreadAttributes: #null *SECURITY_ATTRIBUTES, bInheritHandles: BOOL, dwCreationFlags: DWORD, lpEnvironment: LPVOID, lpCurrentDirectory: LPCSTR, lpStartupInfo: *STARTUPINFOA, lpProcessInformation: *PROCESS_INFORMATION) fail
    {
        if !Win32Priv.CreateProcessA(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation) do
            failWinError(GetLastError())
    }

    func CreateProcessW(lpApplicationName: LPCWSTR, lpCommandLine: LPCWSTR, lpProcessAttributes: #null *SECURITY_ATTRIBUTES, lpThreadAttributes: #null *SECURITY_ATTRIBUTES, bInheritHandles: BOOL, dwCreationFlags: DWORD, lpEnvironment: LPVOID, lpCurrentDirectory: LPCWSTR, lpStartupInfo: *STARTUPINFOW, lpProcessInformation: *PROCESS_INFORMATION) fail
    {
        if !Win32Priv.CreateProcessW(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation) do
            failWinError(GetLastError())
    }

    func CreateJobObjectW(lpJobAttributes: #null *SECURITY_ATTRIBUTES, lpName: #null LPCWSTR)->HANDLE
    {
        return Win32Priv.CreateJobObjectW(lpJobAttributes, lpName)
    }

    func AssignProcessToJobObject(hJob: HANDLE, hProcess: HANDLE) fail
    {
        if !Win32Priv.AssignProcessToJobObject(hJob, hProcess) do
            failWinError(GetLastError())
    }

    #[Discardable]
    func QueryInformationJobObject(hJob: HANDLE, JobObjectInformationClass: DWORD, lpJobObjectInformation: LPVOID, cbJobObjectInformationLength: DWORD, lpReturnLength: #null *DWORD)->bool
    {
        return Win32Priv.QueryInformationJobObject(hJob, JobObjectInformationClass, lpJobObjectInformation, cbJobObjectInformationLength, lpReturnLength) != FALSE
    }

    func SetProcessAffinityMask(hProcess: HANDLE, dwProcessAffinityMask: ULONG_PTR) fail
    {
        if !Win32Priv.SetProcessAffinityMask(hProcess, dwProcessAffinityMask) do
            failWinError(GetLastError())
    }

    func GetExitCodeProcess(hProcess: HANDLE, lpExitCode: LPDWORD) fail
    {
        if !Win32Priv.GetExitCodeProcess(hProcess, lpExitCode) do
            failWinError(GetLastError())
    }

    func TerminateProcess(hProcess: HANDLE, uExitCode: UINT) fail
    {
        if !Win32Priv.TerminateProcess(hProcess, uExitCode) do
            failWinError(GetLastError())
    }

    func MoveFileExW(lpExistingFileName: LPCWSTR, lpNewFileName: #null LPCWSTR, dwFlags: DWORD) fail
    {
        if !Win32Priv.MoveFileExW(lpExistingFileName, lpNewFileName, dwFlags) do
            failWinError(GetLastError())
    }

    func CreatePipe(hReadPipe: *HANDLE, hWritePipe: *HANDLE, lpPipeAttributes: #null const *SECURITY_ATTRIBUTES, nSize: DWORD) fail
    {
        if !Win32Priv.CreatePipe(hReadPipe, hWritePipe, lpPipeAttributes, nSize) do
            failWinError(GetLastError())
    }

    func SetHandleInformation(hObject: HANDLE, dwMask: DWORD, dwFlags: DWORD) fail
    {
        if !Win32Priv.SetHandleInformation(hObject, dwMask, dwFlags) do
            failWinError(GetLastError())
    }

    func CreateEventA(lpEventAttributes: #null *SECURITY_ATTRIBUTES, bManualReset: BOOL, bInitialState: BOOL, lpName: LPCSTR)->HANDLE fail
    {
        let h = Win32Priv.CreateEventA(lpEventAttributes, bManualReset, bInitialState, lpName)
        if !h do
            failWinError(GetLastError())
        return h
    }

    func CreateEventW(lpEventAttributes: #null *SECURITY_ATTRIBUTES, bManualReset: BOOL, bInitialState: BOOL, lpName: LPCWSTR)->HANDLE fail
    {
        let h = Win32Priv.CreateEventW(lpEventAttributes, bManualReset, bInitialState, lpName)
        if !h do
            failWinError(GetLastError())
        return h
    }

    func CreateMutexA(lpMutexAttributes: #null *SECURITY_ATTRIBUTES, bInitialOwner: BOOL, lpName: LPCSTR)->HANDLE fail
    {
        let h = Win32Priv.CreateMutexA(lpMutexAttributes, bInitialOwner, lpName)
        if !h do
            failWinError(GetLastError())
        return h
    }

    func CreateMutexW(lpMutexAttributes: #null *SECURITY_ATTRIBUTES, bInitialOwner: BOOL, lpName: LPCWSTR)->HANDLE fail
    {
        let h = Win32Priv.CreateMutexW(lpMutexAttributes, bInitialOwner, lpName)
        if !h do
            failWinError(GetLastError())
        return h
    }

    func CreateTimerQueueTimer(phNewTimer: *HANDLE, timerQueue: HANDLE, callback: WAITORTIMERCALLBACK, parameter: #null *void, dueTime: DWORD, period: DWORD, flags: ULONG) fail
    {
        if !Win32Priv.CreateTimerQueueTimer(phNewTimer, timerQueue, callback, parameter, dueTime, period, flags) do
            failWinError(GetLastError())
    }

    func DeleteTimerQueueTimer(timerQueue: HANDLE, timer: HANDLE, completionEvent: HANDLE)
    {
        for
        {
            let res = Win32Priv.DeleteTimerQueueTimer(timerQueue, timer, completionEvent)
            if res or GetLastError() == ERROR_IO_PENDING do
                return
        }
    }

    #[Discardable]
    func WriteFile(hFile: HANDLE, lpBuffer: LPCVOID, nNumberOfBytesToWrite: DWORD, lpNumberOfBytesWritten: LPDWORD, lpOverlapped: LPOVERLAPPED)->BOOL fail
    {
        let res = Win32Priv.WriteFile(hFile, lpBuffer, nNumberOfBytesToWrite, lpNumberOfBytesWritten, lpOverlapped)
        if !res and GetLastError() != ERROR_IO_PENDING do
            failWinError(GetLastError())
        return res
    }

    func CreateFileMappingW(hFile: HANDLE, lpFileMappingAttributes: #null *SECURITY_ATTRIBUTES, flProtect: DWORD, dwMaximumSizeHigh: DWORD, dwMaximumSizeLow: DWORD, lpName: LPCWSTR)->HANDLE fail
    {
        let result = Win32Priv.CreateFileMappingW(hFile, lpFileMappingAttributes, flProtect, dwMaximumSizeHigh, dwMaximumSizeLow, lpName)
        if !result do
            failWinError(GetLastError())
        return result
    }

    func MapViewOfFile(hFileMappingObject: HANDLE, dwDesiredAccess: DWORD, dwFileOffsetHigh: DWORD, dwFileOffsetLow: DWORD, dwNumberOfBytesToMap: SIZE_T)->LPVOID fail
    {
        let result = Win32Priv.MapViewOfFile(hFileMappingObject, dwDesiredAccess, dwFileOffsetHigh, dwFileOffsetLow, dwNumberOfBytesToMap)
        if !result do
            failWinError(GetLastError())
        return result
    }

    func UnmapViewOfFile(lpBaseAddress: LPCVOID) fail
    {
        if !Win32Priv.UnmapViewOfFile(lpBaseAddress) do
            failWinError(GetLastError())
    }

    func FlushViewOfFile(lpBaseAddress: LPCVOID, dwNumberOfBytesToFlush: SIZE_T) fail
    {
        if !Win32Priv.FlushViewOfFile(lpBaseAddress, dwNumberOfBytesToFlush) do
            failWinError(GetLastError())
    }

    func DuplicateHandle(hSourceProcessHandle: HANDLE, hSourceHandle: HANDLE, hTargetProcessHandle: HANDLE, lpTargetHandle: *HANDLE, dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwOptions: DWORD) fail
    {
        if !Win32Priv.DuplicateHandle(hSourceProcessHandle, hSourceHandle, hTargetProcessHandle, lpTargetHandle, dwDesiredAccess, bInheritHandle, dwOptions) do
            failWinError(GetLastError())
    }

    #[Discardable]
    func ReadDirectoryChangesW(hDirectory: HANDLE, lpBuffer: LPVOID, nBufferLength: DWORD, bWatchSubtree: BOOL, dwNotifyFilter: DWORD, lpBytesReturned: LPDWORD, lpOverlapped: LPOVERLAPPED, lpCompletionRoutine: #null LPOVERLAPPED_COMPLETION_ROUTINE)->BOOL fail
    {
        let result = Win32Priv.ReadDirectoryChangesW(hDirectory, lpBuffer, nBufferLength, bWatchSubtree, dwNotifyFilter, lpBytesReturned, lpOverlapped, lpCompletionRoutine)
        if !result and GetLastError() != ERROR_IO_PENDING do
            failWinError(GetLastError())
        return result
    }

    func GetOverlappedResult(hFile: HANDLE, lpOverlapped: *OVERLAPPED, lpNumberOfBytesTransferred: *DWORD, bWait: BOOL) fail
    {
        if !Win32Priv.GetOverlappedResult(hFile, lpOverlapped, lpNumberOfBytesTransferred, bWait) do
            failWinError(GetLastError())
    }

    func CancelIoEx(hFile: HANDLE, lpOverlapped: LPOVERLAPPED) fail
    {
        if !Win32Priv.CancelIoEx(hFile, lpOverlapped) do
            failWinError(GetLastError())
    }

    func FileTimeToSystemTime(lpFileTime: const *FILETIME, lpSystemTime: *SYSTEMTIME) fail
    {
        if !Win32Priv.FileTimeToSystemTime(lpFileTime, lpSystemTime) do
            failWinError(GetLastError())
    }

    func SystemTimeToFileTime(lpSystemTime: const *SYSTEMTIME, lpFileTime: *FILETIME) fail
    {
        if !Win32Priv.SystemTimeToFileTime(lpSystemTime, lpFileTime) do
            failWinError(GetLastError())
    }

    func SetFileTime(hFile: HANDLE, lpCreationTime: #null const *FILETIME, lpLastAccessTime: #null const *FILETIME, lpLastWriteTime: #null const *FILETIME) fail
    {
        if !Win32Priv.SetFileTime(hFile, lpCreationTime, lpLastAccessTime, lpLastWriteTime) do
            failWinError(GetLastError())
    }

    func DeleteFileA(lpFileName: LPCSTR) fail
    {
        if !Win32Priv.DeleteFileA(lpFileName) do
            failWinError(GetLastError())
    }

    func DeleteFileW(lpFileName: LPCWSTR) fail
    {
        if !Win32Priv.DeleteFileW(lpFileName) do
            failWinError(GetLastError())
    }

    func GetFileAttributesA(lpFileName: LPCSTR)->DWORD fail
    {
        let attributes = Win32Priv.GetFileAttributesA(lpFileName)
        if attributes == INVALID_FILE_ATTRIBUTES do
            failWinError(GetLastError())
        return attributes
    }

    func GetFileAttributesW(lpFileName: LPCWSTR)->DWORD fail
    {
        let attributes = Win32Priv.GetFileAttributesW(lpFileName)
        if attributes == INVALID_FILE_ATTRIBUTES do
            failWinError(GetLastError())
        return attributes
    }

    func GetFileAttributesExA(lpFileName: LPCSTR, fInfoLevelId: GET_FILEEX_INFO_LEVELS, lpFileInformation: LPVOID) fail
    {
        if !Win32Priv.GetFileAttributesExA(lpFileName, fInfoLevelId, lpFileInformation) do
            failWinError(GetLastError())
    }

    func GetFileAttributesExW(lpFileName: LPCWSTR, fInfoLevelId: GET_FILEEX_INFO_LEVELS, lpFileInformation: LPVOID) fail
    {
        if !Win32Priv.GetFileAttributesExW(lpFileName, fInfoLevelId, lpFileInformation) do
            failWinError(GetLastError())
    }

    func GetCurrentDirectoryA(nBufferLength: DWORD, lpBuffer: LPCSTR)->DWORD fail
    {
        let length = Win32Priv.GetCurrentDirectoryA(nBufferLength, lpBuffer)
        if !length do
            failWinError(GetLastError())
        return length
    }

    func GetCurrentDirectoryW(nBufferLength: DWORD, lpBuffer: LPCWSTR)->DWORD fail
    {
        let length = Win32Priv.GetCurrentDirectoryW(nBufferLength, lpBuffer)
        if !length do
            failWinError(GetLastError())
        return length
    }

    func GetTempPathA(nBufferLength: DWORD, lpBuffer: LPSTR)->DWORD fail
    {
        let length = Win32Priv.GetTempPathA(nBufferLength, lpBuffer)
        if !length do
            failWinError(GetLastError())
        return length
    }

    func GetTempPathW(nBufferLength: DWORD, lpBuffer: LPWSTR)->DWORD fail
    {
        let length = Win32Priv.GetTempPathW(nBufferLength, lpBuffer)
        if !length do
            failWinError(GetLastError())
        return length
    }

    func SetCurrentDirectoryA(lpPathName: LPCSTR) fail
    {
        if !Win32Priv.SetCurrentDirectoryA(lpPathName) do
            failWinError(GetLastError())
    }

    func SetCurrentDirectoryW(lpPathName: LPCWSTR) fail
    {
        if !Win32Priv.SetCurrentDirectoryW(lpPathName) do
            failWinError(GetLastError())
    }

    func CreateFileA(lpFileName: LPCSTR, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: #null *SECURITY_ATTRIBUTES, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: HANDLE)->HANDLE fail
    {
        let h = Win32Priv.CreateFileA(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile)
        if h == INVALID_HANDLE_VALUE do
            failWinError(GetLastError())
        return h
    }

    func CreateFileW(lpFileName: LPCWSTR, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: #null *SECURITY_ATTRIBUTES, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: HANDLE)->HANDLE fail
    {
        let h = Win32Priv.CreateFileW(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile)
        if h == INVALID_HANDLE_VALUE do
            failWinError(GetLastError())
        return h
    }

    func FindFirstFileA(lpFileName: LPCSTR, lpFindFileData: *WIN32_FIND_DATAA)->HANDLE fail
    {
        let res = Win32Priv.FindFirstFileA(lpFileName, lpFindFileData)
        if res == INVALID_HANDLE_VALUE and GetLastError() != ERROR_FILE_NOT_FOUND do
            failWinError(GetLastError())
        return res
    }

    func FindFirstFileW(lpFileName: LPCWSTR, lpFindFileData: *WIN32_FIND_DATAW)->HANDLE fail
    {
        let res = Win32Priv.FindFirstFileW(lpFileName, lpFindFileData)
        if res == INVALID_HANDLE_VALUE and GetLastError() != ERROR_FILE_NOT_FOUND do
            failWinError(GetLastError())
        return res
    }

    func FindFirstFileExA(lpFileName: LPCSTR, fInfoLevelId: FINDEX_INFO_LEVELS, lpFindFileData: LPVOID, fSearchOp: FINDEX_SEARCH_OPS, lpSearchFilter: LPVOID, dwAdditionalFlags: DWORD)->HANDLE fail
    {
        let res = Win32Priv.FindFirstFileExA(lpFileName, fInfoLevelId, lpFindFileData, fSearchOp, lpSearchFilter, dwAdditionalFlags)
        if res == INVALID_HANDLE_VALUE and GetLastError() != ERROR_FILE_NOT_FOUND do
            failWinError(GetLastError())
        return res
    }

    func FindFirstFileExW(lpFileName: LPCWSTR, fInfoLevelId: FINDEX_INFO_LEVELS, lpFindFileData: LPVOID, fSearchOp: FINDEX_SEARCH_OPS, lpSearchFilter: LPVOID, dwAdditionalFlags: DWORD)->HANDLE fail
    {
        let res = Win32Priv.FindFirstFileExW(lpFileName, fInfoLevelId, lpFindFileData, fSearchOp, lpSearchFilter, dwAdditionalFlags)
        if res == INVALID_HANDLE_VALUE and GetLastError() != ERROR_FILE_NOT_FOUND do
            failWinError(GetLastError())
        return res
    }

    func FindNextFileA(hFindFile: HANDLE, lpFindFileData: *WIN32_FIND_DATAA)->BOOL fail
    {
        let res = Win32Priv.FindNextFileA(hFindFile, lpFindFileData)
        if !res and GetLastError() != ERROR_NO_MORE_FILES do
            failWinError(GetLastError())
        return res
    }

    func FindNextFileW(hFindFile: HANDLE, lpFindFileData: *WIN32_FIND_DATAW)->BOOL fail
    {
        let res = Win32Priv.FindNextFileW(hFindFile, lpFindFileData)
        if !res and GetLastError() != ERROR_NO_MORE_FILES do
            failWinError(GetLastError())
        return res
    }

    func FindClose(hFindFile: HANDLE) fail
    {
        if !Win32Priv.FindClose(hFindFile) do
            failWinError(GetLastError())
    }

    func FindFirstVolumeA(lpszVolumeName: LPSTR, cchBufferLength: DWORD)->HANDLE fail
    {
        let res = Win32Priv.FindFirstVolumeA(lpszVolumeName, cchBufferLength)
        if res == INVALID_HANDLE_VALUE do
            failWinError(GetLastError())
        return res
    }

    func FindFirstVolumeW(lpszVolumeName: LPWSTR, cchBufferLength: DWORD)->HANDLE fail
    {
        let res = Win32Priv.FindFirstVolumeW(lpszVolumeName, cchBufferLength)
        if res == INVALID_HANDLE_VALUE do
            failWinError(GetLastError())
        return res
    }

    func FindNextVolumeA(hFindVolume: HANDLE, lpszVolumeName: LPSTR, cchBufferLength: DWORD)->BOOL fail
    {
        let res = Win32Priv.FindNextVolumeA(hFindVolume, lpszVolumeName, cchBufferLength)
        if !res and GetLastError() != ERROR_NO_MORE_FILES do
            failWinError(GetLastError())
        return res
    }

    func FindNextVolumeW(hFindVolume: HANDLE, lpszVolumeName: LPWSTR, cchBufferLength: DWORD)->BOOL fail
    {
        let res = Win32Priv.FindNextVolumeW(hFindVolume, lpszVolumeName, cchBufferLength)
        if !res and GetLastError() != ERROR_NO_MORE_FILES do
            failWinError(GetLastError())
        return res
    }

    func FindVolumeClose(hFindVolume: HANDLE) fail
    {
        if !Win32Priv.FindVolumeClose(hFindVolume) do
            failWinError(GetLastError())
    }

    func GetVolumePathNamesForVolumeNameA(lpszVolumeName: LPCSTR, lpszVolumePathNames: LPCH, cchBufferLength: DWORD, lpcchReturnLength: *DWORD) fail
    {
        if !Win32Priv.GetVolumePathNamesForVolumeNameA(lpszVolumeName, lpszVolumePathNames, cchBufferLength, lpcchReturnLength) do
            failWinError(GetLastError())
    }

    func GetVolumePathNamesForVolumeNameW(lpszVolumeName: LPCWSTR, lpszVolumePathNames: LPWCH, cchBufferLength: DWORD, lpcchReturnLength: *DWORD) fail
    {
        if !Win32Priv.GetVolumePathNamesForVolumeNameW(lpszVolumeName, lpszVolumePathNames, cchBufferLength, lpcchReturnLength) do
            failWinError(GetLastError())
    }

    #[Discardable]
    func SetFilePointer(hFile: HANDLE, lDistanceToMove: LONG, lpDistanceToMoveHigh: PLONG, dwMoveMethod: DWORD)->DWORD fail
    {
        let low = Win32Priv.SetFilePointer(hFile, lDistanceToMove, lpDistanceToMoveHigh, dwMoveMethod)
        if low == INVALID_SET_FILE_POINTER do
            failWinError(GetLastError())
        return low
    }

    func SetFilePointerEx(hFile: HANDLE, liDistanceToMove: LARGE_INTEGER, lpNewFilePointer: #null *LARGE_INTEGER, dwMoveMethod: DWORD) fail
    {
        if !Win32Priv.SetFilePointerEx(hFile, liDistanceToMove, lpNewFilePointer, dwMoveMethod) do
            failWinError(GetLastError())
    }

    func GetFileSize(hFile: HANDLE, lpFileSizeHigh: LPDWORD)->DWORD fail
    {
        let low = Win32Priv.GetFileSize(hFile, lpFileSizeHigh)
        if low == INVALID_FILE_SIZE do
            failWinError(GetLastError())
        return low
    }

    func GetFileSizeEx(hFile: HANDLE, lpFileSize: *LARGE_INTEGER) fail
    {
        if !Win32Priv.GetFileSizeEx(hFile, lpFileSize) do
            failWinError(GetLastError())
    }

    func SetEndOfFile(hFile: HANDLE) fail
    {
        if !Win32Priv.SetEndOfFile(hFile) do
            failWinError(GetLastError())
    }

    func FlushFileBuffers(hFile: HANDLE) fail
    {
        if !Win32Priv.FlushFileBuffers(hFile) do
            failWinError(GetLastError())
    }

    #[Discardable]
    func GetFullPathNameA(lpFileName: LPCSTR, nBufferLength: DWORD, lpBuffer: LPSTR, lpFilePart: #null *LPSTR)->DWORD fail
    {
        let res = Win32Priv.GetFullPathNameA(lpFileName, nBufferLength, lpBuffer, lpFilePart)
        if !res do
            failWinError(GetLastError())
        return res
    }

    #[Discardable]
    func GetFullPathNameW(lpFileName: LPCTSTR, nBufferLength: DWORD, lpBuffer: LPWSTR, lpFilePart: #null *LPWSTR)->DWORD fail
    {
        let res = Win32Priv.GetFullPathNameW(lpFileName, nBufferLength, lpBuffer, lpFilePart)
        if !res do
            failWinError(GetLastError())
        return res
    }

    func CreateDirectoryA(lpPathName: LPCSTR, lpSecurityAttributes: #null *SECURITY_ATTRIBUTES) fail
    {
        let res = Win32Priv.CreateDirectoryA(lpPathName, lpSecurityAttributes)
        if !res do
            failWinError(GetLastError())
    }

    func CreateDirectoryW(lpPathName: LPCWSTR, lpSecurityAttributes: #null *SECURITY_ATTRIBUTES) fail
    {
        let res = Win32Priv.CreateDirectoryW(lpPathName, lpSecurityAttributes)
        if !res do
            failWinError(GetLastError())
    }

    func RemoveDirectoryA(lpPathName: LPCSTR) fail
    {
        let res = Win32Priv.RemoveDirectoryA(lpPathName)
        if !res do
            failWinError(GetLastError())
    }

    func RemoveDirectoryW(lpPathName: LPCWSTR) fail
    {
        let res = Win32Priv.RemoveDirectoryW(lpPathName)
        if !res do
            failWinError(GetLastError())
    }

    func GetUserDefaultLocaleName(lpLocaleName: LPWSTR, cchLocaleName: s32)->s32 fail
    {
        let res = Win32Priv.GetUserDefaultLocaleName(lpLocaleName, cchLocaleName)
        if !res do
            failWinError(GetLastError())
        return res
    }
}
