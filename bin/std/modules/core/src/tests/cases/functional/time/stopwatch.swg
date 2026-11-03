#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var stopwatch: Time.Stopwatch
    Swag.require(not stopwatch.isRunning())
    Swag.require(stopwatch.elapsedTicks() == 0)

    stopwatch.start()
    Swag.require(stopwatch.isRunning())
    Threading.Thread.sleep(2'ms)
    Swag.require(stopwatch.elapsedTicks() > 0)
    Swag.require(stopwatch.elapsedMicroseconds() > 0)

    stopwatch.stop()
    Swag.require(not stopwatch.isRunning())
    let stoppedTicks = stopwatch.elapsedTicks()
    Threading.Thread.sleep(1'ms)
    Swag.require(stopwatch.elapsedTicks() == stoppedTicks)

    stopwatch.restart()
    Swag.require(stopwatch.isRunning())
    stopwatch.reset()
    Swag.require(not stopwatch.isRunning())
    Swag.require(stopwatch.elapsedTicks() == 0)
}

#test
{
    var timing: Time.FrameTiming
    Swag.require(not timing.isPaused)
    timing.pause()
    Swag.require(timing.isPaused)
    timing.resume()
    Swag.require(not timing.isPaused)
}
