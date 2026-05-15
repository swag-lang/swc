#global #if #command == Swag.CompilerCommand.Test
#global #if WINDOWS
#global fileprivate
using Win32

func idleThread(_th: Threading.Thread)
{
}

#test
{
    var thread: Threading.Thread
    discard catch thread.init(&idleThread, null, Threading.ThreadPriority.AboveNormal)
    @assert(@err == null)

    let initPriority = catch GetThreadPriority(cast(HANDLE) thread.handle)
    @assert(@err == null)

    discard catch thread.setPriority(Threading.ThreadPriority.Highest)
    @assert(@err == null)

    let updatedPriority = catch GetThreadPriority(cast(HANDLE) thread.handle)
    @assert(@err == null)

    discard catch thread.start()
    @assert(@err == null)
    thread.wait()

    @assert(initPriority == THREAD_PRIORITY_ABOVE_NORMAL)
    @assert(updatedPriority == THREAD_PRIORITY_HIGHEST)
}
