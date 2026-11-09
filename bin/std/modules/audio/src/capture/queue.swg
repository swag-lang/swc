//! Format: timestamped PCM16 capture blocks.
//! Supported: bounded, thread-safe queues for one to eight interleaved channels.
//! Role: This file joins an OS capture callback to a recorder without retaining unbounded audio.
//
#global public

using Core, Core.Errors

// Describes one captured PCM16 block returned by [[Audio.CaptureQueue.pop]].
struct CaptureBlock
{
    public
    {
        startSample:       u64  // First retained sample frame on the recording timeline.
        firstTick:         u64  // Source timestamp of the first submitted sample frame.
        frameCount:        u32  // Number of sample frames copied to the caller's output.
        gapFrames:         u64  // Missing sample frames since the previous returned block.
        sourceInterrupted: bool // A source loss occurred since the previous returned block.
    }
}

private struct CaptureSlot
{
    startSample: u64
    firstTick:   u64
    frameCount:  u32
    generation:  u64
}

// Transfers timestamped PCM16 from a capture callback to a recorder in bounded memory.
//
// The caller supplies a monotonic `originTick` shared with video and submits each source block
// with its first-sample timestamp. Gaps and overlapping samples are reconciled by
// [[Audio.SampleTimeline]]. A full queue discards its oldest block; the next `pop` reports the
// missing frames. `markLost` and `markRestored` preserve the timeline across device outages.
// The queue itself does not open a microphone; a platform backend supplies its PCM and ticks.
// Producers and consumers may call different methods concurrently.
#[Swag.NoCopy]
struct CaptureQueue
{
    private
    {
        mutex:               Swag.Mutex
        timeline:            SampleTimeline
        slots:               Array'CaptureSlot
        storage:             Array's16
        channels:            u16
        blockFrames:         u32
        slotCount:           u32
        head:                u32
        count:               u32
        deliveredEnd:        u64
        deliveredGeneration: u64
        generation:          u64
        droppedBlocks:       u64
        droppedFrames:       u64
        lost:                bool
    }
}

impl CaptureQueue
{
    // Creates a queue with fixed block and slot limits, using the recording's monotonic clock.
    //
    // The queue allocates `blockFrames * slots * channels * 2` PCM bytes. A block may contain
    // one through `blockFrames` complete frames; `slots` is between one and 64. The origin and
    // source timestamps use `clockFrequency` ticks per second. `tolerance` absorbs small clock
    // jitter in sample frames without hiding larger gaps.
    func create(sampleRate: u32, channels: u16, originTick: u64, clockFrequency: u64,
                blockFrames: u32 = 1_024, slots: u32 = 8, tolerance: u32 = 1)->CaptureQueue fail
    {
        if not channels or channels > 8 or not blockFrames or blockFrames > 4_096 or
           not slots or slots > 64 or tolerance > blockFrames do
            fail BadParameterError{"capture queue needs one to eight channels, 1-4096 frames per block, and 1-64 slots"}
        var result: #returntype
        result.timeline = try SampleTimeline.createWithOrigin(sampleRate, clockFrequency, originTick, tolerance)
        result.channels = channels
        result.blockFrames = blockFrames
        result.slotCount = slots
        result.slots.resize(slots)
        result.storage.resize(cast(u64, slots) * blockFrames * channels)
        return result
    }

    // Returns the configured number of interleaved PCM channels.
    mtd const channelCount()->u16 => .channels

    // Returns the recording sample rate in frames per second.
    mtd const sampleRateHz()->u32 => .timeline.sampleRate

    // Returns the monotonic timestamp clock frequency in ticks per second.
    mtd const clockFrequencyHz()->u64 => .timeline.clockFrequency

    // Returns the maximum frames allowed in one submitted block.
    mtd const maximumBlockFrames()->u32 => .blockFrames

    // Submits one timestamped block from a capture source.
    //
    // The input is copied before return. A fully overlapping block is discarded. If the queue
    // is full, its oldest block is dropped; that loss appears as a gap on a later `pop`.
    // Invalid input or timestamps leave the queue and timeline unchanged.
    mtd push(samples: const [..] s16, firstTick: u64)->SamplePlacement fail
    {
        if not samples.count or samples.count % .channels or
           samples.count / .channels > .blockFrames do
            fail BadParameterError{"capture queue needs one complete nonempty block within its frame limit"}
        .mutex.lock()
        defer .mutex.unlock()
        if .lost do
            fail BadParameterError{"capture source is lost; mark it restored before submitting samples"}

        let placement = try .timeline.place(firstTick, samples.count / .channels)
        if not placement.acceptedFrames do
            return placement
        if .count == .slotCount
        {
            .droppedBlocks += 1
            .droppedFrames += .slots[.head].frameCount
            .head = (.head + 1) % .slotCount
            .count -= 1
        }
        let tail = (.head + .count) % .slotCount
        let slot = &.slots[tail]
        slot.startSample = placement.startSample
        slot.firstTick = firstTick
        slot.frameCount = cast(u32, placement.acceptedFrames)
        slot.generation = .generation
        let offset = cast(u64, tail) * .blockFrames * .channels
        Memory.copy(&.storage[offset], samples.buffer + placement.discardedFrames * .channels,
                    placement.acceptedFrames * .channels * #sizeof(s16))
        .count += 1
        return placement
    }

    // Copies the oldest captured block to `samples` and returns its timing metadata.
    //
    // The output array is cleared even when the queue is empty. On success it contains exactly
    // `info.frameCount * channelCount` interleaved samples. `gapFrames` covers missing source
    // samples and blocks dropped because the queue filled. The caller may reuse both outputs.
    mtd pop(samples: *Array's16, info: *CaptureBlock)->bool
    {
        .mutex.lock()
        defer .mutex.unlock()
        samples.clear()
        if not .count do
            return false
        let slot = .slots[.head]
        let offset = cast(u64, .head) * .blockFrames * .channels
        samples.add(Swag.makeSlice(&.storage[offset], cast(u64, slot.frameCount) * .channels))
        info.startSample = slot.startSample
        info.firstTick = slot.firstTick
        info.frameCount = slot.frameCount
        info.gapFrames = slot.startSample > .deliveredEnd ? slot.startSample - .deliveredEnd : 0
        info.sourceInterrupted = slot.generation != .deliveredGeneration
        .deliveredEnd = slot.startSample + slot.frameCount
        .deliveredGeneration = slot.generation
        .head = (.head + 1) % .slotCount
        .count -= 1
        return true
    }

    // Marks a source outage at a monotonic tick, preserving the recording timeline.
    //
    // Repeated notifications while still lost advance the gap without starting another outage.
    mtd markLost(tick: u64) fail
    {
        .mutex.lock()
        defer .mutex.unlock()
        discard try .timeline.advanceTo(tick)
        if not .lost
        {
            .lost = true
            .generation += 1
        }
    }

    // Marks the source available again, retaining the elapsed gap.
    mtd markRestored(tick: u64) fail
    {
        .mutex.lock()
        defer .mutex.unlock()
        discard try .timeline.advanceTo(tick)
        .lost = false
    }

    // Returns whether the input is currently unavailable.
    mtd sourceIsLost()->bool
    {
        .mutex.lock()
        defer .mutex.unlock()
        return .lost
    }

    // Returns the number of buffered blocks.
    mtd pendingBlocks()->u32
    {
        .mutex.lock()
        defer .mutex.unlock()
        return .count
    }

    // Returns the number of blocks discarded when the queue filled.
    mtd droppedBlockCount()->u64
    {
        .mutex.lock()
        defer .mutex.unlock()
        return .droppedBlocks
    }

    // Returns the number of sample frames discarded when the queue filled.
    mtd droppedFrameCount()->u64
    {
        .mutex.lock()
        defer .mutex.unlock()
        return .droppedFrames
    }

    // Returns the end of submitted audio, including elapsed source gaps.
    mtd sampleEnd()->u64
    {
        .mutex.lock()
        defer .mutex.unlock()
        return .timeline.sampleEnd()
    }

    // Returns a safe silence endpoint while a lost source has no buffered block.
    //
    // The source-loss check and sample-end snapshot share one lock. New blocks submitted after
    // restoration therefore cannot be mistaken for silence by a recorder on another thread.
    // Zero means no idle lost-source gap is available.
    mtd silentGapEnd()->u64
    {
        .mutex.lock()
        defer .mutex.unlock()
        return .lost and not .count ? .timeline.sampleEnd() : 0
    }
}
