#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// Temporary diagnostic: decode a real High 4:4:4 file and report what the planes hold.
#test
{
    Swag.setWorkerCount(4)

    var reader = expect Reader.open("D:/ff-vid/x (1).mp4")
    Swag.print("PROBE size ", reader.width(), "x", reader.height(), " planar ", reader.hasPlanarFrames(), " frames ", reader.frameCount(), "\n")

    var planes: PlanarFrame
    for index in 2'u64
    {
        expect reader.decodeFramePlanesInto(&planes, index)
        Swag.print("PROBE planes ", index, " ", planes.width, "x", planes.height, " shift ", planes.chromaShift, " strideY ", planes.strideLuma, " strideC ", planes.strideChroma, "\n")
        printStats("luma", planes.luma.toSlice())
        printStats("cb", planes.chromaB.toSlice())
        printStats("cr", planes.chromaR.toSlice())
    }

    var image: Image
    expect reader.decodeFrameInto(&image, 0)
    Swag.print("PROBE rgb ", image.width, "x", image.height, "\n")
    printStats("rgb", image.pixels.toSlice())
}

func printStats(name: string, bytes: const [..] u8)
{
    var minimum = 255'u32
    var maximum = 0'u32
    var total   = 0'u64
    for i in bytes.count
    {
        let v = cast(u32) bytes[i]
        minimum = Math.min(minimum, v)
        maximum = Math.max(maximum, v)
        total += cast(u64) v
    }

    Swag.print("PROBE   ", name, " n ", bytes.count, " min ", minimum, " max ", maximum, " mean ", bytes.count ? total / bytes.count : 0, "\n")
}
