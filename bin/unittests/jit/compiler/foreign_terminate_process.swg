#global private
#global if #os == Swag.TargetOs.Windows

// Compile-time code may stop a process it started; only the compiler's own process is out of
// reach. A guard refusing every termination would make a build script that gives up on the
// program it drives impossible to write, so the permitted half is what this checks.

struct StartupInfoW
{
    cb:              u32
    lpReserved:      #null *void
    lpDesktop:       #null *void
    lpTitle:         #null *void
    dwX:             u32
    dwY:             u32
    dwXSize:         u32
    dwYSize:         u32
    dwXCountChars:   u32
    dwYCountChars:   u32
    dwFillAttribute: u32
    dwFlags:         u32
    wShowWindow:     u16
    cbReserved2:     u16
    lpReserved2:     #null *void
    hStdInput:       #null *void
    hStdOutput:      #null *void
    hStdError:       #null *void
}

struct ProcessInformation
{
    hProcess:    #null *void
    hThread:     #null *void
    dwProcessId: u32
    dwThreadId:  u32
}

#[Swag.Foreign("kernel32", "CreateProcessW", callconv: Swag.CallConv.C)]
func CreateProcessW(applicationName: #null const *u16, commandLine: #null *u16, processAttributes: #null *void, threadAttributes: #null *void, inheritHandles: s32, creationFlags: u32, environment: #null *void, currentDirectory: #null const *u16, startupInfo: *StartupInfoW, processInformation: *ProcessInformation)->s32

#[Swag.Foreign("kernel32", "TerminateProcess", callconv: Swag.CallConv.C)]
func TerminateProcess(process: #null *void, exitCode: u32)->s32

#[Swag.Foreign("kernel32", "WaitForSingleObject", callconv: Swag.CallConv.C)]
func WaitForSingleObject(handle: #null *void, milliseconds: u32)->u32

#[Swag.Foreign("kernel32", "GetExitCodeProcess", callconv: Swag.CallConv.C)]
func GetExitCodeProcess(process: #null *void, exitCode: *u32)->s32

#[Swag.Foreign("kernel32", "CloseHandle", callconv: Swag.CallConv.C)]
func CloseHandle(handle: #null *void)->s32

#[Swag.Foreign("kernel32", "MultiByteToWideChar", callconv: Swag.CallConv.C)]
func MultiByteToWideChar(codePage: u32, flags: u32, src: const *u8, srcCount: s32, dst: #null *u16, dstCount: s32)->s32

#test
{
    const CreateSuspended = 0x00000004'u32
    const DetachedProcess = 0x00000008'u32
    const WaitObject0     = 0'u32
    const CodePageUtf8    = 65001'u32

    // The child is created suspended and never runs, so the termination cannot race with a
    // process that was about to exit on its own. It is also detached from the console, so a
    // failure here leaves nothing behind that could hold the output of the suite open.
    var commandLine: [32] u16
    let converted = MultiByteToWideChar(CodePageUtf8, 0'u32, ("cmd.exe").buffer, 7, &commandLine[0], 32)
    Swag.assert(converted == 7)
    commandLine[converted] = 0

    var startup: StartupInfoW
    startup.cb = #sizeof(StartupInfoW)

    var information: ProcessInformation
    Swag.assert(CreateProcessW(null, &commandLine[0], null, null, 0, CreateSuspended | DetachedProcess, null, null, &startup, &information) != 0)

    Swag.assert(TerminateProcess(information.hProcess, 3'u32) != 0)
    Swag.assert(WaitForSingleObject(information.hProcess, 5000'u32) == WaitObject0)

    var exitCode: u32
    Swag.assert(GetExitCodeProcess(information.hProcess, &exitCode) != 0)
    Swag.assert(exitCode == 3'u32)

    discard CloseHandle(information.hThread)
    discard CloseHandle(information.hProcess)
}
