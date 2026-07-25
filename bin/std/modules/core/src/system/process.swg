#global public
#global namespace Env

alias ProcessHandle = #null const *void

struct StartInfo
{
    fileName:  string
    arguments: #null string
}

#[Swag.NoCopy]
struct Process
{
    handle: ProcessHandle
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
