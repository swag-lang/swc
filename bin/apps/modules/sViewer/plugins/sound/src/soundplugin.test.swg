#global if #command == Swag.CompilerCommand.Test
#global private

using Audio

#test
{
    let samples = buildWaveform([0'u8, 128'u8, 255'u8], .Pcm8, 1)
    @assert(samples.count == 3)
    @assert(samples[0] == 1 and samples[1] == 0 and samples[2] > 0.99)
}

#test
{
    let samples = buildWaveform([0'u8, 0x80'u8, 0'u8, 0'u8, 0xFF'u8, 0x7F'u8], .Pcm16, 1)
    @assert(samples.count == 3)
    @assert(samples[0] == 1 and samples[1] == 0 and samples[2] > 0.99)
}
