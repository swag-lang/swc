#global if #command == Swag.CompilerCommand.Test
#global internal

using Core

func testWavU16(bytes: *Array'u8, offset: u64, value: u16)
{
    bytes[offset]     = cast(u8, value & 0xFF)
    bytes[offset + 1] = cast(u8, value >> 8)
}

func testWavU32(bytes: *Array'u8, offset: u64, value: u32)
{
    for index in 4 do
        bytes[offset + index] = cast(u8, (value >> (index * 8)) & 0xFF)
}

// A long, silent recording makes transport positions observable without an audio device.
func testSilentWav(seconds: u32)->Array'u8
{
    const SampleRate = 11_025'u64
    let payload = SampleRate * cast(u64, seconds) * 2
    var bytes: Array'u8
    bytes.resize(44 + payload)
    for index in bytes.count do
        bytes[index] = 0

    const Riff: [4] u8 = [0x52, 0x49, 0x46, 0x46]
    const Wave: [4] u8 = [0x57, 0x41, 0x56, 0x45]
    const Format: [4] u8 = [0x66, 0x6D, 0x74, 0x20]
    const Data: [4] u8 = [0x64, 0x61, 0x74, 0x61]
    for index in 4
    {
        bytes[index]      = Riff[index]
        bytes[8 + index]  = Wave[index]
        bytes[12 + index] = Format[index]
        bytes[36 + index] = Data[index]
    }
    testWavU32(&bytes, 4, cast(u32, 36 + payload))
    testWavU32(&bytes, 16, 16)
    testWavU16(&bytes, 20, 1)
    testWavU16(&bytes, 22, 1)
    testWavU32(&bytes, 24, cast(u32, SampleRate))
    testWavU32(&bytes, 28, cast(u32, SampleRate * 2))
    testWavU16(&bytes, 32, 2)
    testWavU16(&bytes, 34, 16)
    testWavU32(&bytes, 40, cast(u32, payload))
    return bytes
}
