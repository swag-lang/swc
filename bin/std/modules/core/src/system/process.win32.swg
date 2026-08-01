#global if WINDOWS
#global public
#global namespace Env

using Win32, StrConv

// Exit the current process
func exit(exitCode: u32) => ExitProcess(exitCode)

// Starts a new process with arguments
func startProcess(info: StartInfo)->Process fail
{
    Debug.assert(info.fileName != null, "missing process filename")

    var result: retval

    var si: STARTUPINFOA
    var pi: PROCESS_INFORMATION
    si.cb = #sizeof(si)

    // Construct the command line
    var appNameBuilder: StringBuilder
    appNameBuilder.appendString(info.fileName)
    appNameBuilder.zeroTerminate()
    let appName = appNameBuilder.toString()

    var builder: StringBuilder
    builder.appendString("\"")
    builder.appendString(info.fileName)
    builder.appendString("\"")
    if info.arguments
    {
        builder.appendString(" ")
        builder.appendString(info.arguments)
    }

    builder.zeroTerminate()
    let str = builder.toString()

    // Launch
    try CreateProcessA(@dataof(appName), @dataof(str), null, null, FALSE, 0, null, null, &si, &pi)
    CloseHandle(pi.hThread)
    result.handle = pi.hProcess
    return result
}

impl Process
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        .close()
    }

    // Performs the close operation.
    mtd close()
    {
        if .handle
        {
            CloseHandle(.handle)
            .handle = null
        }
    }

    // Wait for the process to be done
    mtd waitForExit()
    {
        Debug.assert(.handle != null, "invalid process handle")
        catch WaitForSingleObject(.handle, Win32.INFINITE)
        .close()
    }

    // Returns the current operating-system process identifier.
    func currentProcessId()->u64 => GetCurrentProcessId()

    // Returns the current operating-system thread identifier.
    func currentThreadId()->u64 => GetCurrentThreadId()
}
