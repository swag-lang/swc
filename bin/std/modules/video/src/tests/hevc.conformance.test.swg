#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors

// Network abstraction layer unit types and the payload type that carries a picture digest.
const PrefixSeiNal              = 39'u32
const SuffixSeiNal              = 40'u32
const DecodedPictureHashPayload = 132'u32

// Decodes an elementary H.265 byte stream and checks every picture against the digest the stream
// carries for it.
//
// A conformance bitstream states the digest of each decoded picture in a supplemental enhancement
// information message, so the stream is its own reference: a picture that reconstructs to anything
// other than what the standard says produces a different digest, and the first picture that does
// says where the decoder went wrong. Nothing here trusts this module's own encoders.
struct ConformanceRun
{
    decoder:      Hevc.Decoder
    expected:     Array'String
    produced:     Array'String
    pictureCount: u32
    hashCount:    u32
}

impl ConformanceRun
{
    // Runs one Annex B byte stream through the decoder.
    mtd run(path: string) fail
    {
        // Whether a wavefront picture is decoded row by row or one row per worker is read from
        // the pool, so this file run on its own would never reach the concurrent path.
        if Jobs.isSynchronous() do
            try Jobs.initialize(16)

        let bytes = try File.readAllBytes(path)
        let data  = bytes.toSlice()

        // Annex B frames every unit with a three or four byte start code.
        var starts: Array'u64
        var index = 0'u64
        while index + 3 <= data.count
        {
            if data[index] == 0 and data[index + 1] == 0 and data[index + 2] == 1
            {
                starts.add(index + 3)
                index += 3
                continue
            }

            index += 1
        }

        for entry in starts.count
        {
            let first = starts[entry]
            var last  = entry + 1 < starts.count ? starts[entry + 1] - 3 : data.count

            // A start code may carry a leading zero byte that belongs to neither unit.
            while last > first and data[last - 1] == 0 do
                last -= 1
            if last <= first do
                continue

            let unit    = data[first until last]
            let nalType = cast(u32) (unit[0] >> 1) & 0x3F
            if nalType == PrefixSeiNal or nalType == SuffixSeiNal
            {
                .readHashMessages(unit)
                continue
            }

            let started = try .decoder.readNalUnit(unit)
            if started and .decoder.finishedFrame
            {
                .recordPicture(.decoder.finishedFrame!)
                .decoder.finishedFrame = null
            }
        }

        let last = try .decoder.finishPicture()
        if last do
            .recordPicture(last!)
    }

    // Reads the decoded picture digests out of one supplemental enhancement information unit.
    private mtd readHashMessages(unit: const [..] u8)
    {
        var payload: Array'u8
        unescapeRbsp(&payload, unit[2 until unit.count])
        let bytes = payload.toSlice()

        var offset = 0'u64
        while offset + 2 < bytes.count
        {
            var payloadType = 0'u32
            while offset < bytes.count and bytes[offset] == 0xFF
            {
                payloadType += 255
                offset      += 1
            }

            if offset >= bytes.count do
                return
            payloadType += cast(u32) bytes[offset]
            offset      += 1

            var payloadSize = 0'u64
            while offset < bytes.count and bytes[offset] == 0xFF
            {
                payloadSize += 255
                offset      += 1
            }

            if offset >= bytes.count do
                return
            payloadSize += cast(u64) bytes[offset]
            offset      += 1

            if offset + payloadSize > bytes.count do
                return
            if payloadType == DecodedPictureHashPayload and payloadSize > 0 do
                .readPictureHash(bytes[offset until offset + payloadSize])
            offset += payloadSize
        }
    }

    // Reads one `decoded_picture_hash` message, clause D.2.19.
    private mtd readPictureHash(payload: const [..] u8)
    {
        // Only the message digest form is read; the two checksum forms would need their own
        // implementations and no stream this suite carries uses them.
        if payload[0] != 0 do
            return

        var text: String
        for index in 1 until payload.count do
            appendHexByte(&text, payload[index])
        .expected.add(#move text)
        .hashCount += 1
    }

    // Computes the digest of one decoded picture the way clause D.3.19 states it.
    private mtd recordPicture(frame: *Hevc.Frame)
    {
        // The harness shows every picture immediately, so the buffer may reuse it at once.
        frame.outputNeeded = false
        .pictureCount      += 1

        let sps = .decoder.activeSps
        if !sps do
            return

        var text: String
        for component in 3'u32
        {
            let bitDepth = component == 0 ? sps!.bitDepthLuma : sps!.bitDepthChroma
            let width    = component == 0 ? sps!.width : sps!.width / sps!.subWidthC
            let height   = component == 0 ? sps!.height : sps!.height / sps!.subHeightC
            let stride   = component == 0 ? frame.strideLuma : frame.strideChroma
            let plane    = component == 0 ? frame.luma.buffer! : (component == 1 ? frame.chromaB.buffer! : frame.chromaR.buffer!)
            let origin   = cast(u64) Hevc.FramePadding * stride + cast(u64) Hevc.FramePadding

            var digest: Hash.Md5
            digest.reset()

            // A sample wider than eight bits contributes two bytes, least significant first.
            var row: Array'u8
            row.resize(cast(u64) width * (bitDepth > 8 ? 2 : 1))
            let output = row.buffer!

            for y in height
            {
                let line = origin + cast(u64) y * stride
                if bitDepth > 8
                {
                    for x in width
                    {
                        let value = plane[line + cast(u64) x]
                        output[cast(u64) x * 2]     = cast(u8) (value & 0xFF)
                        output[cast(u64) x * 2 + 1] = cast(u8) (value >> 8)
                    }
                }
                else
                {
                    for x in width do
                        output[x] = cast(u8) plane[line + cast(u64) x]
                }

                digest.update(row.toSlice())
            }

            text.append(Hash.Md5.toString(digest.finalize()))
        }

        .produced.add(#move text)
    }

    // Returns the first picture whose digest differs, or minus one when they all agree.
    mtd const firstMismatch()->s32
    {
        let count = Math.min(.expected.count, .produced.count)
        for index in count
        {
            if .expected[index] != .produced[index] do
                return cast(s32) index
        }

        return -1
    }
}

// Appends one byte as two uppercase hexadecimal digits.
func appendHexByte(text: *String, value: u8)
{
    const Digits = "0123456789ABCDEF"
    text.append(Digits[cast(u64) (value >> 4)])
    text.append(Digits[cast(u64) (value & 15)])
}

// Decodes one conformance bitstream and requires every picture to match its own digest.
func checkConformance(name: string, pictures: u32)
{
    var run: ConformanceRun
    expect run.run(videoFixturePath(name).toString())

    Swag.assert(run.pictureCount == pictures)
    Swag.assert(run.hashCount == pictures)
    Swag.assert(run.firstMismatch() < 0)
}

// Every intra prediction mode, at every transform size, in an intra-only stream.
#test
{
    checkConformance("hevc-ipred-a-docomo-2.bit", 20)
}

// Merge candidate derivation at every permitted candidate count.
#test
{
    checkConformance("hevc-merge-a-ti-3.bit", 8)
}

// Temporal motion vector prediction, which reads the motion a reference picture exported.
#test
{
    checkConformance("hevc-tmvp-a-ms-3.bit", 17)
}

// Sample adaptive offset with random merge decisions, over intra and predicted pictures.
#test
{
    checkConformance("hevc-sao-a-mediatek-4.bit", 60)
}

// Ten-bit samples decoded through wavefront parallel processing, with independent and dependent
// slice segments and a quantization parameter that moves inside every transform unit. This is the
// combination a modern encoder produces, and the one the entropy synchronization has to survive.
#test
{
    checkConformance("hevc-wpp-a-ericsson-main10-2.bit", 48)
}
