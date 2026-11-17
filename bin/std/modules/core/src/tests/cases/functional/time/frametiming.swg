#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var timing = Time.FrameTiming{minimumDeltaSeconds: 10, maximumDeltaSeconds: 20}

    timing.update()
    timing.update()

    Swag.require(timing.frameCount == 2)
    Swag.require(timing.deltaSeconds == timing.minimumDeltaSeconds)
}

#test
{
    var timing = Time.FrameTiming{minimumDeltaSeconds: 0.00001, maximumDeltaSeconds: 0.001}

    timing.update()
    Threading.Thread.sleep(10'ms)
    timing.update()

    Swag.require(timing.frameCount == 2)
    Swag.require(timing.deltaSeconds == timing.maximumDeltaSeconds)
}

#test
{
    var timing       = Time.FrameTiming{}
    let initialDelta = timing.deltaSeconds
    timing.pause()
    timing.update()
    Swag.require(timing.isPaused and timing.frameCount == 0 and timing.deltaSeconds == initialDelta)

    timing.resume()
    Swag.require(not timing.isPaused)
    timing.resume()
    timing.update()
    Swag.require(timing.frameCount == 1)
    Swag.require(timing.deltaSeconds >= timing.minimumDeltaSeconds)
    Swag.require(timing.deltaSeconds <= timing.maximumDeltaSeconds)
}
