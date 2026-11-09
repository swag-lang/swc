#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// A failed reopen advances the gap; recovery marks the next block as interrupted.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000,
                                           blockFrames: 2, tolerance: 0)
    var recovery = expect CaptureRecovery.create(&queue, 1_000)
    const First: [2] s16 = [10, 20]
    const Second: [2] s16 = [30, 40]
    discard expect queue.push(Swag.makeSlice(&First[0], First.count), 0)
    expect recovery.deviceLost(2)
    Swag.require(recovery.isLost() and queue.sourceIsLost())
    Swag.require(recovery.nextRetryTick() == 1_002)
    Swag.require(not recovery.retryDue(1_001) and recovery.retryDue(1_002))
    expect recovery.retryFailed(1_002)
    Swag.require(recovery.nextRetryTick() == 2_002 and queue.sampleEnd() == 1_002)
    expect recovery.deviceRestored(2_500)
    Swag.require(not recovery.isLost() and not queue.sourceIsLost())
    discard expect queue.push(Swag.makeSlice(&Second[0], Second.count), 2_500)

    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and not info.sourceInterrupted)
    Swag.require(queue.pop(&samples, &info))
    Swag.require(info.startSample == 2_500 and info.gapFrames == 2_498)
    Swag.require(info.sourceInterrupted and not recovery.retryDue(9_000))
    Swag.require(Slice.equals(samples.toSlice(), Second))
}

// Duplicate loss notices do not move the next retry; early retries fail atomically.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000, tolerance: 0)
    var recovery = expect CaptureRecovery.create(&queue, 100)
    expect recovery.deviceLost(10)
    expect recovery.deviceLost(50)
    Swag.require(recovery.nextRetryTick() == 110 and queue.sampleEnd() == 50)
    var rejected: Swag.Error
    discard catch recovery.retryFailed(109) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(recovery.nextRetryTick() == 110 and queue.sampleEnd() == 50)
    expect recovery.deviceRestored(110)
    expect recovery.deviceRestored(111)
    discard catch recovery.retryFailed(210) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(queue.sampleEnd() == 110 and not recovery.isLost())
}

// Invalid intervals and overflowing deadlines leave the source available.
#test
{
    var queue = expect CaptureQueue.create(1, 1, 0, 1, tolerance: 0)
    var rejected: Swag.Error
    discard catch CaptureRecovery.create(&queue, 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    var recovery = expect CaptureRecovery.create(&queue, 2)
    discard catch recovery.deviceLost(Swag.U64.Max - 1) as rejected
    Swag.require(rejected.value() is OverflowError)
    Swag.require(not recovery.isLost() and not queue.sourceIsLost() and queue.sampleEnd() == 0)
    expect recovery.deviceLost(1)
    discard catch CaptureRecovery.create(&queue, 1) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// Four hours of missed retries keep constant state and one precise sample gap.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000,
                                           blockFrames: 1, slots: 2, tolerance: 0)
    var recovery = expect CaptureRecovery.create(&queue, 1_000)
    const Sample: [1] s16 = [7]
    discard expect queue.push(Swag.makeSlice(&Sample[0], 1), 0)
    expect recovery.deviceLost(1)
    for second in 1 until 4 * 60 * 60
    {
        let tick = second * 1_000 + 1
        Swag.require(recovery.retryDue(tick))
        expect recovery.retryFailed(tick)
    }
    expect recovery.deviceRestored(4'u64 * 60 * 60 * 1_000)
    discard expect queue.push(Swag.makeSlice(&Sample[0], 1), 4'u64 * 60 * 60 * 1_000)
    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.gapFrames == 0)
    Swag.require(queue.pop(&samples, &info))
    Swag.require(info.startSample == 14_400_000 and info.gapFrames == 14_399_999)
    Swag.require(info.sourceInterrupted and queue.droppedBlockCount() == 0)
}
