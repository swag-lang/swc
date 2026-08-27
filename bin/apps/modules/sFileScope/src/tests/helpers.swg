#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui

// Completes a viewer worker deterministically, then lets the headless GUI publish its result.
func(T) completeViewerBackgroundLoad(host: *Testing.HeadlessHost, load: *ViewerBackgroundLoad'T, timer: #null *Timer)
{
    @assert(load.started and timer != null)
    Jobs.wait(&load.job)
    host.fireTimer(timer)
}

// Completes file classification without waiting for the selected viewer's own background work.
func completeViewerWindowClassification(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while !window.pendingFile.isEmpty() and steps < 4_096
    {
        if window.choiceLoad.started and !window.choiceLoad.isDone() do
            Threading.Thread.sleep(1'ms)
        if window.startupTimer do
            host.fireTimer(window.startupTimer)
        steps += 1
    }

    @assert(window.pendingFile.isEmpty())
}
