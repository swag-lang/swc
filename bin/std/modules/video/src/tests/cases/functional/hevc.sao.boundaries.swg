#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Four 32x32 coding tree blocks make every side and diagonal neighbour explicit.
#[Swag.NoCopy]
struct SaoPicture
{
    sps:     Hevc.Sps
    pps:     Hevc.Pps
    frame:   Hevc.Frame
    decoder: Hevc.Decoder
}

impl SaoPicture
{
    mtd initialize()
    {
        .sps.width          = 64
        .sps.height         = 64
        .sps.ctbSize        = 32
        .sps.widthInCtbs    = 2
        .sps.heightInCtbs   = 2
        .sps.sizeInCtbs     = 4
        .sps.subWidthC      = 2
        .sps.subHeightC     = 2
        .sps.bitDepthLuma   = 8
        .sps.bitDepthChroma = 8
        .sps.saoEnabled     = true
        .frame.prepare(&.sps)

        for y in 64_s32
        {
            for x in 64_s32
            {
                .frame.lumaAtMutable(x, y)[0] = 100
            }
        }

        .decoder.activeSps = &.sps
        .decoder.activePps = &.pps
        .decoder.current   = &.frame
        .decoder.saoUsed   = true
        .decoder.sao.resize(4)
        .decoder.ctbRsToTs.add([0_u32, 1, 2, 3])
        .decoder.tileId.resize(4)
        .decoder.ctbSliceAddr.resize(4)
        .decoder.ctbSliceIndex.resize(4)
        .decoder.sliceParams.add(Hevc.SliceDeblock{false, true, 0, 0})
    }

    mtd enableEdge(block: u32, kind: u8)
    {
        .decoder.sao[block].typeIdx[0]   = 2
        .decoder.sao[block].eoClass[0]   = kind
        .decoder.sao[block].offsets[0, 2] = 2
        .decoder.sao[block].offsets[0, 3] = -2
    }
}

// The tile map is in tile-scan order, while the SAO parameters and slice map use raster order.
#test
{
    for acrossTiles in [false, true]
    {
        var picture: SaoPicture
        picture.initialize()
        picture.pps.tilesEnabled = true
        picture.pps.loopFilterAcrossTiles = acrossTiles
        picture.decoder.ctbRsToTs[1] = 2
        picture.decoder.ctbRsToTs[2] = 1
        picture.decoder.tileId[2]    = 1
        picture.decoder.tileId[3]    = 1
        picture.enableEdge(0, 0)
        picture.enableEdge(1, 0)

        for y in 64_s32
        {
            for x in 32_s32 until 64
            {
                picture.frame.lumaAtMutable(x, y)[0] = 110
            }
        }

        picture.decoder.applySampleAdaptiveOffset()
        Swag.require(picture.frame.lumaAtMutable(31, 15)[0] == (acrossTiles ? 102 : 100))
        Swag.require(picture.frame.lumaAtMutable(32, 15)[0] == (acrossTiles ? 108 : 110))
    }
}

// An L-shaped slice has one unavailable diagonal and two available side neighbours.
#test
{
    for acrossSlices in [false, true]
    {
        var picture: SaoPicture
        picture.initialize()
        picture.decoder.sliceParams.add(Hevc.SliceDeblock{false, acrossSlices, 0, 0})
        for block in 1 until 4
        {
            picture.decoder.ctbSliceAddr[block]  = 1
            picture.decoder.ctbSliceIndex[block] = 1
        }

        picture.enableEdge(3, 2)
        picture.frame.lumaAtMutable(31, 31)[0] = 110
        picture.decoder.applySampleAdaptiveOffset()
        Swag.require(picture.frame.lumaAtMutable(32, 32)[0] == (acrossSlices ? 102 : 100))
    }
}

// A forbidden top edge still admits a corner whose diagonal neighbour is in the same slice.
#test
{
    var picture: SaoPicture
    picture.initialize()
    picture.decoder.sliceParams.add(Hevc.SliceDeblock{false, false, 0, 0})
    for block in 1 until 4
    {
        picture.decoder.ctbSliceAddr[block]  = 1
        picture.decoder.ctbSliceIndex[block] = 1
    }

    picture.enableEdge(2, 3)
    picture.frame.lumaAtMutable(32, 31)[0] = 110
    picture.frame.lumaAtMutable(29, 31)[0] = 110
    picture.decoder.applySampleAdaptiveOffset()
    Swag.require(picture.frame.lumaAtMutable(31, 32)[0] == 102)
    Swag.require(picture.frame.lumaAtMutable(28, 32)[0] == 100)
}

func requireSaoReferencePlane(actual: const [..] u8, expected: const [*] u8, main10: bool)
{
    if not main10
    {
        Swag.require(Memory.compare(actual.buffer, expected, actual.count) == 0)
        return
    }

    for index in actual.count
    {
        let offset = index * 2
        let sample = cast(u32, expected[offset]) | (cast(u32, expected[offset + 1]) << 8)
        Swag.require(actual[index] == Math.min((sample + 2) >> 2, 255_u32))
    }
}

// FFmpeg 9.1 reference planes for a sequence with a horizontal slice boundary at luma y=32.
#test
{
    const Luma   = 96 * 64
    const Chroma = Luma / 4
    for main10 in [false, true]
    {
        let stem     = main10 ? "ffmpeg-hevc-sao-boundary-main10" : "ffmpeg-hevc-sao-boundary-main"
        let expected = expect File.readAllBytes(videoFixturePath(Format.toString("%.yuv", stem).toString()))
        let bytesPerSample = main10 ? 2_u64 : 1
        for extension in ["hevc", "mp4"]
        {
            var reader = expect Reader.open(videoFixturePath(Format.toString("%.%",
                     stem, extension).toString()))
            Swag.require(reader.width() == 96 and reader.height() == 64)
            Swag.require(reader.frameCount() == 5 and expected.count == 5 * (Luma + 2 * Chroma) * bytesPerSample)
            var picture: PlanarFrame
            for index in reader.frameCount()
            {
                expect reader.decodeFramePlanesInto(&picture, index)
                let offset = expected.storage() + index * (Luma + 2 * Chroma) * bytesPerSample
                requireSaoReferencePlane(picture.luma.toSlice(), offset, main10)
                requireSaoReferencePlane(picture.chromaB.toSlice(), offset + Luma * bytesPerSample, main10)
                requireSaoReferencePlane(picture.chromaR.toSlice(), offset + (Luma + Chroma) * bytesPerSample, main10)
            }
        }
    }
}

func requireNativeSaoFrame(picture: *Hevc.Frame, expected: const [..] u8, index: u64)
{
    Swag.require(picture.bitDepth == 10)
    var offset = index * 96 * 64 * 3
    for component in 3
    {
        let width  = component == 0 ? 96 : 48
        let height = component == 0 ? 64 : 32
        let stride = component == 0 ? picture.strideLuma : picture.strideChroma
        let plane  = component == 0 ? picture.luma.storage() : (component == 1 ? picture.chromaB.storage() : picture.chromaR.storage())
        let start  = cast(u64, Hevc.FramePadding) * (stride + 1)
        for y in height
        {
            let row = plane + start + y * stride
            for x in width
            {
                let sample = cast(u16, expected[offset]) | (cast(u16, expected[offset + 1]) << 8)
                Swag.require(row[x] == sample)
                offset += 2
            }
        }
    }

    picture.outputNeeded = false
}

// Preserving the planar API's output also preserves every native ten-bit sample.
#test
{
    let name      = "ffmpeg-hevc-sao-boundary-main10"
    let stream    = expect File.readAllBytes(videoFixturePath(Format.toString("%.hevc", name).toString()))
    let reference = expect File.readAllBytes(videoFixturePath(Format.toString("%.yuv", name).toString()))
    var source    = ByteSource.openMemory(stream.toSlice())
    var scanner: AnnexBScanner
    expect scanner.open(&source)

    var decoder: Hevc.Decoder
    var unit: AnnexBNal
    var index = 0_u64
    while expect scanner.next(&source, &unit)
    {
        let started = expect decoder.readNalUnit(stream.toSlice()[unit.payload until unit.payload + unit.size])
        if started and decoder.finishedFrame
        {
            requireNativeSaoFrame(decoder.finishedFrame, reference.toSlice(), index)
            decoder.finishedFrame = null
            index += 1
        }
    }

    let last = unwrap expect decoder.finishPicture()
    requireNativeSaoFrame(last, reference.toSlice(), index)
    Swag.require(index + 1 == 5)
}
