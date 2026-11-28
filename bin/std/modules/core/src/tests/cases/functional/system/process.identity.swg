#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// The current process and calling thread keep stable, nonzero identifiers during a test.
#test
{
    let processId = Env.Process.currentProcessId()
    let threadId  = Env.Process.currentThreadId()

    Swag.require(processId != 0)
    Swag.require(threadId != 0)
    Swag.require(Env.Process.currentProcessId() == processId)
    Swag.require(Env.Process.currentThreadId() == threadId)
}
