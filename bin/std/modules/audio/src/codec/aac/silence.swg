//! Format: MPEG-4 AAC Low Complexity silent access units.
//! Supported: Mono and stereo, 1024 samples per packet, indexed sample rates.
//! Role: This file supplies encoded silence while an input device is unavailable.
//
#global namespace Aac
#global export

using Core, Core.Errors

private const SilenceRates: [12] u32 = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000,
                                       24_000, 22_050, 16_000, 12_000, 11_025, 8_000]
private const MonoSilence:   [4] u8 = [0x00, 0x00, 0x00, 0x07]
private const StereoSilence: [7] u8 = [0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0E]

// Supplies silent AAC-LC packets without allocating or retaining PCM data.
//
// Each raw access unit decodes to 1024 zero-valued frames after the decoder's preceding overlap
// has drained. Use its AudioSpecificConfig and packets with a container writer; the packet has no
// ADTS header. A recorder can submit repeated packets to keep an AAC track continuous while its
// microphone or loopback source is unavailable. It still chooses the packet count and timestamps.
struct SilenceEncoder
{
    private
    {
        config:    [2] u8
        channels:  u16
        sampleRate: u32
    }
}

impl SilenceEncoder
{
    // Creates a silent packet source for one or two channels at an indexed AAC sample rate.
    func create(sampleRate: u32, channels: u16)->SilenceEncoder fail
    {
        if channels != 1 and channels != 2 do
            fail BadParameterError{"AAC silence encoder needs one or two channels"}
        for rate, index in SilenceRates where rate == sampleRate
        {
            let value = (2'u16 << 11) | (cast(u16, index) << 7) | (channels << 3)
            var result: #returntype
            result.config[0]  = cast(u8, value >> 8)
            result.config[1]  = cast(u8, value & 0xFF)
            result.channels   = channels
            result.sampleRate = sampleRate
            return result
        }
        fail BadParameterError{"AAC silence encoder needs an indexed sample rate"}
    }

    // Returns the borrowed two-byte AAC-LC AudioSpecificConfig for this source.
    mtd const decoderConfig()->const [..] u8 => Swag.makeSlice(&.config[0], .config.count)

    // Returns one borrowed raw AAC-LC access unit representing 1024 sample frames.
    mtd const packet()->const [..] u8
        => .channels == 1 ? Swag.makeSlice(&MonoSilence[0], MonoSilence.count) :
                            Swag.makeSlice(&StereoSilence[0], StereoSilence.count)

    // Returns the number of sample frames per packet.
    mtd const packetFrames()->u32 => 1_024

    // Returns this source's sample rate in frames per second.
    mtd const sampleRateHz()->u32 => .sampleRate

    // Returns this source's channel count.
    mtd const channelCount()->u16 => .channels
}
