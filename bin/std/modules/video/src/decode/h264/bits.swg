//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 Baseline, Main, and High-profile streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, non-4:2:0 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns bounded RBSP bit reading and Exp-Golomb decoding.
//
#global namespace H264
#global internal

using Core, Core.Errors

// Reads the bits of one raw byte sequence payload, most significant bit first.
//
// Reading past the end returns zero bits and records the overrun instead of failing on the
// spot, so the innermost entropy loops carry no failure path; the parser checks [[overran]]
// once per syntax structure and reports one error for the whole run.
struct BitReader
{
    data:    #null const [*] u8     // Payload bytes, already free of emulation-prevention bytes.
    size:    u64                    // Number of payload bytes.
    bitPos:  u64                    // Read position, in bits from the first byte.
    overran: bool                   // Whether a read ran past the end of the payload.
}

impl BitReader
{
    mtd init(payload: const [..] u8)
    {
        .data    = @dataof(payload)
        .size    = @countof(payload)
        .bitPos  = 0
        .overran = false
    }

    // Returns the number of unread bits.
    mtd const bitsLeft()->u64 => .bitPos >= .size * 8 ? 0 : .size * 8 - .bitPos

    // Reads one bit.
    mtd bit()->u32
    {
        if .bitPos >= .size * 8
        {
            .overran = true
            return 0
        }

        let value = (.data![.bitPos >> 3] >> cast(u32) (7 - (.bitPos & 7))) & 1
        .bitPos += 1
        return value
    }

    // Reads `count` bits as an unsigned value. `count` is at most 32.
    mtd read(count: u32)->u32
    {
        var result = 0'u32
        for count do
            result = (result << 1) | .bit()
        return result
    }

    // Returns the next 16 bits without consuming them, padding past the end with zeros.
    mtd const peek16()->u32
    {
        var result    = 0'u32
        let byteIndex = .bitPos >> 3
        for offset in 3'u64
        {
            result <<= 8
            if byteIndex + offset < .size do
                result |= cast(u32) .data![byteIndex + offset]
        }

        return (result >> cast(u32) (8 - (.bitPos & 7))) & 0xFFFF
    }

    // Advances the read position by `count` bits.
    mtd skip(count: u32)
    {
        .bitPos += count
        if .bitPos > .size * 8
        {
            .bitPos  = .size * 8
            .overran = true
        }
    }

    // Reads one unsigned Exp-Golomb value.
    mtd ue()->u32
    {
        var zeros = 0'u32
        while !.bit()
        {
            zeros += 1
            if zeros > 31 or .overran
            {
                .overran = true
                return 0
            }
        }

        if !zeros do
            return 0
        return (1'u32 << zeros) - 1 + .read(zeros)
    }

    // Reads one signed Exp-Golomb value.
    mtd se()->s32
    {
        let code      = .ue()
        let magnitude = cast(s32) ((code + 1) >> 1)
        return code & 1 ? magnitude : -magnitude
    }

    // Reports whether more syntax follows, before the trailing stop bit of the payload.
    mtd const moreData()->bool
    {
        if .overran or .bitPos >= .size * 8 do
            return false

        // The payload ends with a stop bit and zero padding; data remains only when a set bit
        // exists after the read position and is not the last set bit of the payload.
        var lastSet = .size * 8
        while lastSet > .bitPos
        {
            lastSet -= 1
            let value = (.data![lastSet >> 3] >> cast(u32) (7 - (lastSet & 7))) & 1
            if value do
                break
        }

        return lastSet > .bitPos
    }
}

// Appends the raw byte sequence payload of one NAL unit, removing emulation-prevention bytes.
//
// `data` is the NAL payload after its header byte. The destination is reset first and reused
// across NAL units, so a decoder unescapes a whole stream with one allocation.
func unescapeRbsp(destination: *Array'u8, data: const [..] u8)
{
    let count = @countof(data)
    destination.clear()
    if !count do
        return
    destination.resize(count)
    let output             = destination.buffer!
    var index, outputIndex = 0'u64
    var zeros              = 0'u32
    let threes             = Math.Simd.splat(3'u8)
    while index < count
    {
        if count - index >= 16
        {
            let bytes = Math.Simd.load(@dataof(data) + index)
            if !Math.Simd.anyTrue(bytes == threes)
            {
                Math.Simd.store(output + outputIndex, bytes)
                outputIndex += 16
                index       += 16
                if data[index - 1] == 0
                {
                    zeros = data[index - 2] == 0 ? 2 : 1
                }
                else
                {
                    zeros = 0
                }

                continue
            }
        }

        let value = data[index]
        if zeros >= 2 and value == 3
        {
            zeros = 0
            index += 1
            continue
        }

        zeros               = value == 0 ? zeros + 1 : 0
        output[outputIndex] = value
        outputIndex         += 1
        index               += 1
    }

    destination.resize(outputIndex)
}
