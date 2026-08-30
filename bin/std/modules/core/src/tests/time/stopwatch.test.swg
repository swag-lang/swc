#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var stopwatch: Time.Stopwatch
    Swag.assert(!stopwatch.isRunning())
    Swag.assert(stopwatch.elapsedTicks() == 0)

    stopwatch.start()
    Swag.assert(stopwatch.isRunning())
    Threading.Thread.sleep(2'ms)
    Swag.assert(stopwatch.elapsedTicks() > 0)
    Swag.assert(stopwatch.elapsedMicroseconds() > 0)

    stopwatch.stop()
    Swag.assert(!stopwatch.isRunning())
    let stoppedTicks = stopwatch.elapsedTicks()
    Threading.Thread.sleep(1'ms)
    Swag.assert(stopwatch.elapsedTicks() == stoppedTicks)

    stopwatch.restart()
    Swag.assert(stopwatch.isRunning())
    stopwatch.reset()
    Swag.assert(!stopwatch.isRunning())
    Swag.assert(stopwatch.elapsedTicks() == 0)
}

#test
{
    var timing: Time.FrameTiming
    Swag.assert(!timing.isPaused)
    timing.pause()
    Swag.assert(timing.isPaused)
    timing.resume()
    Swag.assert(!timing.isPaused)
}
