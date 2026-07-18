#global public
#global namespace Env
#global #[Swag.ExplicitNullability]

alias ProcessHandle = #null const *void

struct StartInfo
{
    fileName:      #nonull string
    arguments:     #null string
}

#[Swag.NoCopy]
struct Process
{
    handle: ProcessHandle
}

// Starts a new process with arguments
func startProcess(fileName: #nonull string, arguments: #null string = null)->Process throw
{
    let info = StartInfo{fileName: fileName, arguments: arguments}
    return try startProcess(info)
}

// Starts a new process with arguments, and wait for it to be done
func doSyncProcess(fileName: #nonull string, arguments: #null string = null) throw
{
    var h = try startProcess(fileName, arguments)
    h.waitForExit()
}
