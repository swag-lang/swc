#global if WINDOWS
#global public
#global namespace Debugger

using Win32

// Returns whether a debugger is attached to the current process.
func isAttached()->bool => cast(bool) IsDebuggerPresent()

// Raises a breakpoint exception, which stops the process in an attached debugger.
func debugBreak() => DebugBreak()

// Sends `msg` to the output window of an attached debugger.
func log(msg: string)
{
    // The debugger reads up to the terminator, which a 'string' view does not guarantee.
    let text = String.from(msg)
    OutputDebugStringA(text.buffer)
}

// Opens the Visual Studio just-in-time debugger dialog for this process and waits until a debugger attaches.
//
// Fails when the dialog cannot be started. The wait has no timeout: dismissing the dialog
// without attaching leaves the process waiting.
func attach() fail
{
    let arguments = Format.toString("-p %", GetCurrentProcessId())

    // Dropping the process value closes its launcher handles without waiting for attachment.
    discard try Env.startProcess("vsjitdebugger.exe", arguments.toString())

    while not IsDebuggerPresent() do
        Threading.Thread.sleep(100'ms)
}
