#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Temporary bench: encodes film clips and prints size and time; a script measures quality.
func benchClip(name: string, width, height: s32, qp: u32, slices: u32)
{
    const SourceWidth = 2664'u64
    const SourceHeight = 1078'u64
    const Frames = 30'u64
    let frameBytes = SourceWidth * SourceHeight * 3 / 2
    let bytes = expect File.readAllBytes(Format.toString("C:/Users/chris/AppData/Local/Temp/claude/5a81f6a1d1e5a74c/9999d5da-e754-40d1-8ec9-52e0f8635722/scratchpad/enc/%.nv12", name))
    Swag.require(bytes.count == Frames * frameBytes)

    let path = Path.combine(testSourceRoot(#curlocation), Format.toString("../../benchtmp/swagenc-%-%x%-q%.mp4", name, width, height, qp).toString())
    var encoder = expect H264.Encoder.create(width, height, 250, qp, slices)
    var writer  = expect Mp4.FragmentedWriter.create(path, width, height, 90_000, encoder.decoderConfig())
    var packed: Array'u8
    packed.resize(cast(u64, width) * cast(u64, height) * 3 / 2)
    var total = 0'u64
    var keyBytes = 0'u64
    var watch: Time.Stopwatch
    var elapsed = 0'u64
    for index in Frames
    {
        let source = bytes.storage() + index * frameBytes
        for row in cast(u64, height) do
            Memory.copy(packed.storage() + row * cast(u64, width), source + row * SourceWidth, cast(u64, width))
        for row in cast(u64, height) / 2 do
            Memory.copy(packed.storage() + (cast(u64, height) + row) * cast(u64, width), source + (SourceHeight + row) * SourceWidth, cast(u64, width))
        var frame: Nv12Frame
        frame.copyPacked(width, height, packed.toSlice())
        watch.restart()
        let packet = expect encoder.encode(&frame, index * 3000, 3000)
        watch.stop()
        elapsed += watch.elapsedMicroseconds()
        total += packet.bytes.count
        if packet.isKeyFrame do
            keyBytes += packet.bytes.count
        expect writer.addPacket(packet)
    }
    expect writer.end()
    let picture = encoder.lossy.reference()
    var recon: Array'u8
    for row in cast(s32, height) do
        recon.add(Swag.makeSlice(picture.pixLuma(0, row), cast(u64, width)))
    discard expect File.writeAllBytes(Format.toString("%.recon", path), recon.toSlice())
    Console.print("ENCBENCH ", name, " ", width, "x", height, " qp ", qp, " bytes ", total, " key ", keyBytes, " kbps ", total * 8 / 1000, " ms ", elapsed / 1000 / Frames, " file ", path, " ;\n")
}

#test
{
    for name in ["dark", "bright", "mid"]
    {
        benchClip(name, 2664, 1078, 26, 8)
    }
}
