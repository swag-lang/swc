#global public
#global namespace Env

// Names the process handle type.
alias ProcessHandle = #null const *void

// Represents start info.
struct StartInfo
{
    fileName:  string           // File name associated with this value.
    arguments: #null string     // Arguments associated with this value.
}

// Represents process.
#[Swag.NoCopy]
struct Process
{
    handle: ProcessHandle     // Handle associated with this value.
}

// Starts a new process with arguments
func startProcess(fileName: string, arguments: #null string = null)->Process fail
{
    let info = StartInfo{fileName: fileName, arguments: arguments}
    return try startProcess(info)
}

// Starts a new process with arguments, and wait for it to be done
func doSyncProcess(fileName: string, arguments: #null string = null) fail
{
    var h = try startProcess(fileName, arguments)
    h.waitForExit()
}
