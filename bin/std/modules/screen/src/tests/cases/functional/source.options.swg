#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

private func assertInvalidSourceOptions(options: SourceOptions)
{
    var failure: Swag.Error
    discard catch Source.open(options) as failure
    Swag.require(failure.value() is BadParameterError)
}

private func assertInvalidMonitorIndex(monitorIndex: u64)
{
    var failure: Swag.Error
    discard catch Source.openMonitor(monitorIndex) as failure
    Swag.require(failure.value() is BadParameterError)
}

private func assertInvalidMonitor(monitor: Env.Monitor)
{
    var failure: Swag.Error
    discard catch Source.openMonitor(monitor) as failure
    Swag.require(failure.value() is BadParameterError)
}

// Shared dimension validation rejects invalid values before opening a display or allocating a frame.
#test
{
    assertInvalidSourceOptions({0, 0, 0, 1, false})
    assertInvalidSourceOptions({0, 0, 1, 0, false})
    assertInvalidSourceOptions({0, 0, -1, 1, false})
    assertInvalidSourceOptions({0, 0, 1, -1, false})
    assertInvalidSourceOptions({0, 0, Swag.S32.Max, 1, false})
    expect validateSourceOptions({0, 0, Swag.S32.Max / 4, 1, false})

    assertInvalidMonitorIndex(Swag.U64.Max)
    assertInvalidMonitor({})
}

// QPC presentation stamps use the same microsecond scale as Core.Time.
#test
{
    Swag.require(qpcTicksToMicroseconds(0, 10_000_000) == 0)
    Swag.require(qpcTicksToMicroseconds(10_000_000, 10_000_000) == 1_000_000)
    Swag.require(qpcTicksToMicroseconds(15_000_000, 10_000_000) == 1_500_000)
    Swag.require(qpcTicksToMicroseconds(1, 10_000_000) == 0)
    Swag.require(qpcTicksToMicroseconds(1, 3) == 333_333)
    Swag.require(qpcTicksToMicroseconds(2, 3) == 666_666)
    Swag.require(qpcTicksToMicroseconds(1, 0) == 0)
}

// Frame age is absent until a fresh frame has been delivered.
#test
{
    Swag.require(frameAgeAt(100, 0) == 0)
    Swag.require(frameAgeAt(100, 40) == 60)
    Swag.require(frameAgeAt(100, 100) == 0)

    var source: Source
    Swag.require(source.frameAgeMicroseconds() == 0)
    source.lastFrameCaptureTime = Time.monotonicMicroseconds() - 60
    Swag.require(source.frameAgeMicroseconds() >= 60)
}

// Both arrays have room before source acquisition starts.
#test
{
    var source: Source
    source.reservePartStorage(2)
    Swag.require(source.sources.capacity >= 2 and source.pictures.capacity >= 2)
}

// A replacement image cannot reuse pixels retained for a different target.
#test
{
    var target = Image.create(8, 4, .BGRA8)
    var cached = Image.create(8, 4, .BGRA8)
    Memory.set(target.pixels.storage(), 0x00, target.byteCount)
    Memory.set(cached.pixels.storage(), 0x37, cached.byteCount)
    let imageAddress   = cast(u64, &target)
    let storageAddress = cast(u64, target.pixels.storage())

    Swag.require(targetMatchesImage(&target, 8, 4, imageAddress, storageAddress, true))
    Swag.require(not copyCachedFrameIfNeeded(&target,
                                             cached.pixels.storage(),
                                             8,
                                             4,
                                             imageAddress,
                                             storageAddress,
                                             true,
                                             false))
    Swag.require(Memory.compare(target.pixels.storage(), cached.pixels.storage(), target.byteCount) != 0,
                 "an unchanged reusable target should remain untouched")
    Swag.require(not targetMatchesImage(&target, 8, 4, imageAddress, storageAddress + 1, true))
    Swag.require(not targetMatchesImage(&target, 8, 4, imageAddress + 1, storageAddress, true))
    Swag.require(not targetMatchesImage(&target, 7, 4, imageAddress, storageAddress, true))

    var replacement = Image.create(8, 4, .BGRA8)
    Memory.set(replacement.pixels.storage(), 0xAA, replacement.byteCount)
    Swag.require(copyCachedFrameIfNeeded(&replacement,
                                         cached.pixels.storage(),
                                         8,
                                         4,
                                         imageAddress,
                                         storageAddress,
                                         true,
                                         false))
    Swag.require(Memory.compare(replacement.pixels.storage(), cached.pixels.storage(), cached.byteCount) == 0,
                 "a replacement target should receive the cached frame")
}

// Reset clears every source and native metric without opening a display.
#test
{
    var source: Source
    let native = Memory.new'NativeSource()
    native[].metrics = SourceMetrics{acquiredFrames: 1,
                                     unchangedFrames: 1,
                                     coalescedUpdates: 1,
                                     acquireMicroseconds: 1,
                                     maxAcquireMicroseconds: 1,
                                     changeDetectionMicroseconds: 1,
                                     readbackMicroseconds: 1,
                                     maxReadbackMicroseconds: 1,
                                     deferredReadbacks: 1,
                                     copyMicroseconds: 1,
                                     outputMicroseconds: 1,
                                     composeMicroseconds: 1,
                                     partialFrames: 1,
                                     multiRectFrames: 1,
                                     copiedPixels: 1,
                                     mirroredPixels: 1}
    source.sources.add(native)
    source.composeMicroseconds = 1
    source.mirroredPixels      = 1

    source.resetMetrics()
    let metrics = source.metrics()
    Swag.require(metrics.acquiredFrames == 0 and
                 metrics.unchangedFrames == 0 and
                 metrics.coalescedUpdates == 0 and
                 metrics.acquireMicroseconds == 0 and
                 metrics.maxAcquireMicroseconds == 0 and
                 metrics.changeDetectionMicroseconds == 0 and
                 metrics.readbackMicroseconds == 0 and
                 metrics.maxReadbackMicroseconds == 0 and
                 metrics.deferredReadbacks == 0 and
                 metrics.copyMicroseconds == 0 and
                 metrics.outputMicroseconds == 0 and
                 metrics.composeMicroseconds == 0 and
                 metrics.partialFrames == 0 and
                 metrics.multiRectFrames == 0 and
                 metrics.copiedPixels == 0 and
                 metrics.mirroredPixels == 0)
    Swag.require(native[].metrics.mirroredPixels == 0)
}
