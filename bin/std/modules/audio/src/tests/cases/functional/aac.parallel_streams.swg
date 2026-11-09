#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

private func recordPacket(bytes: *Array'u8, packet: const [..] u8)
{
    if not packet.count do
        return
    bytes.add(cast(u8, packet.count & 255))
    bytes.add(cast(u8, (packet.count >> 8) & 255))
    bytes.add(packet)
}

func encodeTwoStreams(alternate: bool, first: *Array'u8, second: *Array'u8) fail
{
    first.clear()
    second.clear()
    var stereo = try Aac.StreamEncoder.create(48_000, 2)
    var mono = try Aac.StreamEncoder.create(44_100, 1, .Voice)
    var leftRight: [2_500 * 2] s16
    var single: [3_300] s16
    for frame in 2_500
    {
        leftRight[frame * 2] = cast(s16, cast(s32, frame * 37 % 20_000) - 10_000)
        leftRight[frame * 2 + 1] = cast(s16, cast(s32, frame * 61 % 17_000) - 8_500)
    }
    for frame in 3_300 do
        single[frame] = cast(s16, cast(s32, frame * 29 % 14_000) - 7_000)
    var packet: Array'u8
    var stereoCursor = 0'u64
    var monoCursor = 0'u64
    while stereoCursor < 2_500 or monoCursor < 3_300
    {
        if stereoCursor < 2_500
        {
            let count = Math.min(137'u64, 2_500'u64 - stereoCursor)
            stereoCursor += try stereo.push(Swag.makeSlice(&leftRight[stereoCursor * 2], count * 2),
                                            &packet)
            recordPacket(first, packet.toSlice())
        }
        if monoCursor < 3_300 and (alternate or stereoCursor == 2_500)
        {
            let count = Math.min(91'u64, 3_300'u64 - monoCursor)
            monoCursor += try mono.push(Swag.makeSlice(&single[monoCursor], count), &packet)
            recordPacket(second, packet.toSlice())
        }
    }
    if alternate
    {
        var stereoDone = false
        var monoDone = false
        while not stereoDone or not monoDone
        {
            if not stereoDone
            {
                stereoDone = not (try stereo.finish(&packet))
                recordPacket(first, packet.toSlice())
            }
            if not monoDone
            {
                monoDone = not (try mono.finish(&packet))
                recordPacket(second, packet.toSlice())
            }
        }
    }
    else
    {
        while try stereo.finish(&packet) do
            recordPacket(first, packet.toSlice())
        while try mono.finish(&packet) do
            recordPacket(second, packet.toSlice())
    }
    Swag.require(stereo.inputFrameCount() == 2_500 and stereo.packetCount() == 4 and
                 mono.inputFrameCount() == 3_300 and mono.packetCount() == 5)
}

// Two simultaneous AAC tracks keep their packet bytes independent of call ordering.
#test
{
    var sequentialStereo: Array'u8
    var sequentialMono: Array'u8
    var alternateStereo: Array'u8
    var alternateMono: Array'u8
    expect encodeTwoStreams(false, &sequentialStereo, &sequentialMono)
    expect encodeTwoStreams(true, &alternateStereo, &alternateMono)
    Swag.require(Slice.equals(sequentialStereo.toSlice(), alternateStereo.toSlice()) and
                 Slice.equals(sequentialMono.toSlice(), alternateMono.toSlice()))
}
