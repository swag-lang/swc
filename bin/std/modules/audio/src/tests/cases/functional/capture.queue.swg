#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

struct CaptureConcurrentSource
{
    late queue: *CaptureQueue
    done: s32
}

func produceCaptureBlocks(thread: const *Threading.Thread)
{
    let source = cast(*CaptureConcurrentSource, unwrap thread.userParam)
    var block: [16] s16
    for index in 10_000
    {
        block[0] = cast(s16, index)
        discard expect source.queue.push(Swag.makeSlice(&block[0], block.count), index * 16)
    }
    discard Swag.atomicExchange(&source.done, 1)
}

// A simulated microphone supplies ordered blocks with a shared recording clock.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000, blockFrames: 4, slots: 3, tolerance: 0)
    Swag.require(queue.sampleRateHz() == 1_000 and queue.clockFrequencyHz() == 1_000)
    const First: [3] s16 = [10, 20, 30]
    const Second: [2] s16 = [40, 50]
    let first = expect queue.push(Swag.makeSlice(&First[0], First.count), 0)
    let second = expect queue.push(Swag.makeSlice(&Second[0], Second.count), 3)
    Swag.require(first.startSample == 0 and first.acceptedFrames == 3)
    Swag.require(second.startSample == 3 and second.acceptedFrames == 2)
    Swag.require(queue.pendingBlocks() == 2 and queue.sampleEnd() == 5)

    var samples: Array's16
    var info = CaptureBlock{startSample: 5, firstTick: 7, frameCount: 1,
                            gapFrames: 2, sourceInterrupted: true}
    Swag.require(queue.pop(&samples, &info))
    Swag.require(info.startSample == 0 and info.firstTick == 0 and info.frameCount == 3)
    Swag.require(info.gapFrames == 0 and not info.sourceInterrupted)
    Swag.require(Slice.equals(samples.toSlice(), First))
    Swag.require(queue.pop(&samples, &info))
    Swag.require(info.startSample == 3 and info.firstTick == 3 and info.frameCount == 2)
    Swag.require(info.gapFrames == 0 and not info.sourceInterrupted)
    Swag.require(Slice.equals(samples.toSlice(), Second))
    Swag.require(not queue.pop(&samples, &info) and samples.isEmpty())
    Swag.require(info.startSample == 0 and info.firstTick == 0 and info.frameCount == 0 and
                 info.gapFrames == 0 and not info.sourceInterrupted)
}

// Timestamp gaps survive; overlapping source frames are discarded before enqueueing.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000, blockFrames: 4, tolerance: 0)
    const First: [4] s16 = [1, 2, 3, 4]
    const Second: [3] s16 = [5, 6, 7]
    const Third: [4] s16 = [8, 9, 10, 11]
    discard expect queue.push(Swag.makeSlice(&First[0], First.count), 0)
    let gap = expect queue.push(Swag.makeSlice(&Second[0], Second.count), 7)
    let overlap = expect queue.push(Swag.makeSlice(&Third[0], Third.count), 9)
    Swag.require(gap.silenceFrames == 3 and gap.acceptedFrames == 3)
    Swag.require(overlap.discardedFrames == 1 and overlap.acceptedFrames == 3)

    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.gapFrames == 0)
    Swag.require(queue.pop(&samples, &info) and info.startSample == 7 and info.gapFrames == 3)
    Swag.require(Slice.equals(samples.toSlice(), Second))
    Swag.require(queue.pop(&samples, &info) and info.startSample == 10 and info.gapFrames == 0)
    Swag.require(Slice.equals(samples.toSlice(), [9's16, 10, 11]))
}

// Frames clipped by committed silence retain their original sample-grid offset.
#test
{
    var queue = expect CaptureQueue.create(10, 1, 0, 100, blockFrames: 10, tolerance: 0)
    const Initial: [10] s16 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    discard expect queue.push(Initial, 0)
    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.startSample == 0 and info.frameCount == 10)
    discard expect queue.markSilentUntil(100)

    const Late: [2] s16 = [1, 2]
    let placement = expect queue.push(Late, 96)
    Swag.require(placement.discardedFrames == 1 and placement.acceptedFrames == 1)
    Swag.require(queue.pop(&samples, &info))
    Swag.require(info.startSample == 11 and info.gapFrames == 1 and info.frameCount == 1)
    Swag.require(samples[0] == 2 and queue.sampleEnd() == 12)
}

// Clipping uses exact sample offsets even when the clock has fewer ticks than the sample rate.
#test
{
    var queue = expect CaptureQueue.create(3, 1, 0, 2, blockFrames: 4, tolerance: 0)
    const Initial: [1] s16 = [0]
    discard expect queue.push(Initial, 0)
    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.startSample == 0 and info.frameCount == 1)
    discard expect queue.markSilentUntil(1)

    const Late: [4] s16 = [1, 2, 3, 4]
    let placement = expect queue.push(Late, 0)
    Swag.require(placement.discardedFrames == 2 and placement.acceptedFrames == 2)
    Swag.require(queue.pop(&samples, &info))
    Swag.require(info.startSample == 2 and info.gapFrames == 1 and info.frameCount == 2)
    Swag.require(samples[0] == 3 and samples[1] == 4)
}

// A full ring drops only its oldest block and exposes the missing samples to the consumer.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000, blockFrames: 2, slots: 2, tolerance: 0)
    const First: [2] s16 = [1, 2]
    const Second: [2] s16 = [3, 4]
    const Third: [2] s16 = [5, 6]
    discard expect queue.push(Swag.makeSlice(&First[0], First.count), 0)
    discard expect queue.push(Swag.makeSlice(&Second[0], Second.count), 2)
    discard expect queue.push(Swag.makeSlice(&Third[0], Third.count), 4)
    Swag.require(queue.pendingBlocks() == 2)
    Swag.require(queue.droppedBlockCount() == 1 and queue.droppedFrameCount() == 2)

    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.startSample == 2 and info.gapFrames == 2)
    Swag.require(Slice.equals(samples.toSlice(), Second))
    Swag.require(queue.pop(&samples, &info) and info.startSample == 4 and info.gapFrames == 0)
    Swag.require(Slice.equals(samples.toSlice(), Third))
}

// Device outage and recovery report a gap and a source-interruption generation.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000, blockFrames: 2, tolerance: 0)
    const First: [2] s16 = [10, 20]
    const Second: [2] s16 = [30, 40]
    const Last: [1] s16 = [50]
    discard expect queue.push(Swag.makeSlice(&First[0], First.count), 0)
    expect queue.markLost(2)
    expect queue.markLost(5)
    Swag.require(queue.sourceIsLost() and queue.sampleEnd() == 5)
    var rejected: Swag.Error
    discard catch queue.push(Swag.makeSlice(&Second[0], Second.count), 5) as rejected
    Swag.require(rejected.value() is BadParameterError)
    expect queue.markRestored(10)
    Swag.require(not queue.sourceIsLost())
    discard expect queue.push(Swag.makeSlice(&Second[0], Second.count), 10)

    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and not info.sourceInterrupted)
    Swag.require(queue.pop(&samples, &info))
    Swag.require(info.startSample == 10 and info.gapFrames == 8 and info.sourceInterrupted)
    Swag.require(Slice.equals(samples.toSlice(), Second))

    expect queue.markLost(12)
    expect queue.markRestored(16)
    discard expect queue.push(Swag.makeSlice(&Last[0], Last.count), 16)
    Swag.require(queue.pop(&samples, &info) and info.startSample == 16)
    Swag.require(info.gapFrames == 4 and info.sourceInterrupted and queue.sampleEnd() == 17)
}

// Invalid layouts, blocks, and clocks leave queued audio intact.
#test
{
    var rejected: Swag.Error
    discard catch CaptureQueue.create(1_000, 0, 0, 1_000) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch CaptureQueue.create(1_000, 1, 0, 1_000, blockFrames: 4_097) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch CaptureQueue.create(1_000, 1, 0, 1_000, slots: 257) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch CaptureQueue.create(0, 1, 0, 1_000) as rejected
    Swag.require(rejected.value() is BadParameterError)

    var queue = expect CaptureQueue.create(1_000, 2, 100, 1_000, blockFrames: 2, tolerance: 0)
    const Stereo: [4] s16 = [1, 10, 2, 20]
    discard expect queue.push(Swag.makeSlice(&Stereo[0], Stereo.count), 100)
    discard catch queue.push(Swag.makeSlice(&Stereo[0], 3), 102) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch queue.push(Swag.makeSlice(&Stereo[0], Stereo.count), 99) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(queue.pendingBlocks() == 1 and queue.sampleEnd() == 2)
    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.startSample == 0)
    Swag.require(Slice.equals(samples.toSlice(), Stereo))
}

// Long-running producer activity never expands the ring or loses its sample position.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000, blockFrames: 16, slots: 4, tolerance: 0)
    var block: [16] s16
    for index in 10_000
    {
        block[0] = cast(s16, index)
        discard expect queue.push(Swag.makeSlice(&block[0], block.count), index * 16)
    }
    Swag.require(queue.pendingBlocks() == 4 and queue.sampleEnd() == 160_000)
    Swag.require(queue.droppedBlockCount() == 9_996 and queue.droppedFrameCount() == 159_936)
    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.startSample == 159_936)
    Swag.require(info.gapFrames == 159_936 and samples[0] == 9_996)
}

// A producer callback and recorder may use the ring concurrently without torn blocks.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000, blockFrames: 16, slots: 256, tolerance: 0)
    var source = CaptureConcurrentSource{queue: &queue}
    var thread: Threading.Thread
    discard expect thread.init(&produceCaptureBlocks, &source)
    discard expect thread.start()

    var samples: Array's16
    var info: CaptureBlock
    var previousEnd = 0'u64
    while Swag.atomicLoad(&source.done) == 0 or queue.pendingBlocks() != 0
    {
        if queue.pop(&samples, &info)
        {
            Swag.require(info.startSample >= previousEnd)
            Swag.require(info.gapFrames == info.startSample - previousEnd)
            Swag.require(info.frameCount == 16 and samples.count == 16)
            Swag.require(samples[0] == cast(s16, info.startSample / 16))
            previousEnd = info.startSample + info.frameCount
        }
        else do
            Threading.Thread.yield()
    }
    thread.wait()
    Swag.require(queue.sampleEnd() == 160_000 and queue.pendingBlocks() == 0)
}

// A four-hour source outage is represented by one gap rather than buffered silence.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 1_000_000_000,
                                           blockFrames: 1, slots: 2, tolerance: 0)
    const Sample: [1] s16 = [123]
    discard expect queue.push(Swag.makeSlice(&Sample[0], 1), 0)
    expect queue.markLost(20_834)
    let resumedTick = 4'u64 * 60 * 60 * 1_000_000_000
    expect queue.markRestored(resumedTick)
    discard expect queue.push(Swag.makeSlice(&Sample[0], 1), resumedTick)
    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.gapFrames == 0)
    Swag.require(queue.pop(&samples, &info))
    Swag.require(info.startSample == 691_200_000 and info.gapFrames == 691_199_999)
    Swag.require(info.sourceInterrupted and queue.pendingBlocks() == 0)
    Swag.require(queue.sampleEnd() == 691_200_001)
}

// The queue can feed a streaming sound-only recording with explicit silence at missing times.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-capture-queue-%.wav", Guid128.random()))
    defer discard catch File.delete(path)
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000, blockFrames: 2, tolerance: 0)
    const First: [2] s16 = [10, 20]
    const Second: [2] s16 = [30, 40]
    discard expect queue.push(Swag.makeSlice(&First[0], First.count), 0)
    discard expect queue.push(Swag.makeSlice(&Second[0], Second.count), 4)
    var writer = expect Wav.Writer.create(path.toString(), 1, 1_000)
    var samples: Array's16
    var info: CaptureBlock
    while queue.pop(&samples, &info)
    {
        expect writer.addSilence(info.gapFrames)
        expect writer.addFrames(samples.toSlice())
    }
    expect writer.end()
    let sound = expect SoundFile.load(path.toString())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(Slice.equals(decoded.toSlice(), [10's16, 20, 0, 0, 30, 40]))
}

// Simulated microphone loss becomes a silent AAC packet between two captured tones.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-capture-queue-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 1_024, tolerance: 0)
    var signal: [1_024] s16
    var silence: [1_024] s16
    for frame in 1_024 do
        signal[frame] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                 1_000.0 * frame / 48_000.0)))
    discard expect queue.push(Swag.makeSlice(&signal[0], signal.count), 0)
    discard expect queue.push(Swag.makeSlice(&signal[0], signal.count), 2_048)

    var encoder = expect Aac.StreamEncoder.create(48_000, 1)
    var file: Array'u8
    var packets: Array'SoundPacket
    var captured: Array's16
    var packet: Array'u8
    var info: CaptureBlock
    while queue.pop(&captured, &info)
    {
        if info.gapFrames
        {
            Swag.require(info.gapFrames == 1_024)
            Swag.require(expect encoder.push(Swag.makeSlice(&silence[0], silence.count), &packet) == 1_024)
            packets.add({file.count, cast(u32, packet.count), 1_024})
            file.add(packet.toSlice())
        }
        Swag.require(expect encoder.push(captured.toSlice(), &packet) == 1_024)
        packets.add({file.count, cast(u32, packet.count), 1_024})
        file.add(packet.toSlice())
    }
    while expect encoder.finish(&packet)
    {
        packets.add({file.count, cast(u32, packet.count), 1_024})
        file.add(packet.toSlice())
    }
    Swag.require(packets.count == 4 and encoder.inputFrameCount() == 3 * 1_024)
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 1,
                                                  4 * 1_024, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == 4 * 1_024)
    var before = 0.0'f64
    var gap = 0.0'f64
    var after = 0.0'f64
    for frame in 1_024
    {
        before += cast(f64, decoded[1_024 + frame]) * decoded[1_024 + frame]
        gap += cast(f64, decoded[2_048 + frame]) * decoded[2_048 + frame]
        after += cast(f64, decoded[3_072 + frame]) * decoded[3_072 + frame]
    }
    Swag.require(Math.sqrt(before / 1_024) > 4_000)
    Swag.require(Math.sqrt(gap / 1_024) < 500)
    Swag.require(Math.sqrt(after / 1_024) > 4_000)
}
