#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var stopwatch: Time.Stopwatch
    @assert(!stopwatch.isRunning())
    @assert(stopwatch.elapsedTicks() == 0)

    stopwatch.start()
    @assert(stopwatch.isRunning())
    Threading.Thread.sleep(2'ms)
    @assert(stopwatch.elapsedTicks() > 0)
    @assert(stopwatch.elapsedMicroseconds() > 0)

    stopwatch.stop()
    @assert(!stopwatch.isRunning())
    let stoppedTicks = stopwatch.elapsedTicks()
    Threading.Thread.sleep(1'ms)
    @assert(stopwatch.elapsedTicks() == stoppedTicks)

    stopwatch.restart()
    @assert(stopwatch.isRunning())
    stopwatch.reset()
    @assert(!stopwatch.isRunning())
    @assert(stopwatch.elapsedTicks() == 0)
}

#test
{
    var timing: Time.FrameTiming
    @assert(!timing.isPaused)
    timing.pause()
    @assert(timing.isPaused)
    timing.resume()
    @assert(!timing.isPaused)
}
