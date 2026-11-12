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
    var timing = Time.FrameTiming{minimumDeltaSeconds: 0.02, maximumDeltaSeconds: 0.02}
    Swag.require(not timing.isPaused)
    let initialDelta = timing.deltaSeconds

    timing.update()
    Swag.require(timing.frameCount == 1)
    Swag.require(timing.deltaSeconds == initialDelta)

    timing.update()
    Swag.require(timing.frameCount == 2)
    Swag.require(timing.deltaSeconds == 0.02)

    timing.pause()
    Swag.require(timing.isPaused)
    let pausedDelta = timing.deltaSeconds
    timing.update()
    Swag.require(timing.frameCount == 2)
    Swag.require(timing.deltaSeconds == pausedDelta)

    timing.resume()
    Swag.require(not timing.isPaused)
    timing.update()
    Swag.require(timing.frameCount == 3)
    Swag.require(timing.deltaSeconds == 0.02)
}

#test
{
    var stopwatch: Time.Stopwatch

    stopwatch.start()
    Threading.Thread.sleep(2'ms)
    let firstElapsed = stopwatch.elapsedTicks()
    Swag.require(firstElapsed > 0)

    stopwatch.start()
    Swag.require(stopwatch.elapsedTicks() >= firstElapsed)
    Threading.Thread.sleep(2'ms)
    stopwatch.stop()
    let stoppedElapsed = stopwatch.elapsedTicks()
    Swag.require(stoppedElapsed >= firstElapsed)

    Threading.Thread.sleep(1'ms)
    stopwatch.stop()
    Swag.require(stopwatch.elapsedTicks() == stoppedElapsed)
}
