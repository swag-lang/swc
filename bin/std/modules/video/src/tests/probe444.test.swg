#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// Temporary diagnostic: decode a real High 4:4:4 file against the planes FFmpeg produced.
#test
{
    Swag.setWorkerCount(4)

    var reader = expect Reader.open("C:/Users/chris/AppData/Local/Temp/claude/c--Perso-swag-lang-swc/918533df-fa5c-4a8c-acc5-1eb6af7fd67f/scratchpad/cut444.mp4")
    let width  = reader.width()
    let height = reader.height()
    Swag.print("PROBE size ", width, "x", height, " frames ", reader.frameCount(), "\n")

    let reference = expect File.readAllBytes("C:/Users/chris/AppData/Local/Temp/claude/c--Perso-swag-lang-swc/918533df-fa5c-4a8c-acc5-1eb6af7fd67f/scratchpad/cut_ref.yuv")
    let planeSize = cast(u64) width * cast(u64) height

    var planes: PlanarFrame
    for index in 6'u64
    {
        expect reader.decodeFramePlanesInto(&planes, index)
        let at = index * planeSize * 3
        comparePlane("luma", index, width, planes.luma.toSlice(), reference.toSlice()[at until at + planeSize])
        comparePlane("cb", index, width, planes.chromaB.toSlice(), reference.toSlice()[at + planeSize until at + planeSize * 2])
        comparePlane("cr", index, width, planes.chromaR.toSlice(), reference.toSlice()[at + planeSize * 2 until at + planeSize * 3])
    }
}

func comparePlane(name: string, index: u64, width: s32, actual, expected: const [..] u8)
{
    var differing = 0'u64
    var worst     = 0'u32
    var firstAt   = Swag.U64.Max
    var mbs:  HashSet'u64
    for i in actual.count
    {
        let delta = cast(u32) Math.abs(cast(s32) actual[i] - cast(s32) expected[i])
        if delta
        {
            differing += 1
            worst = Math.max(worst, delta)
            firstAt = Math.min(firstAt, i)
            let x = cast(s32) (i % cast(u64) width)
            let y = cast(s32) (i / cast(u64) width)
            mbs.add(cast(u64) ((y / 16) * 1000 + x / 16))
        }
    }

    if !differing
    {
        Swag.print("PROBE frame ", index, " ", name, " exact\n")
        return
    }

    let x = cast(s32) (firstAt % cast(u64) width)
    let y = cast(s32) (firstAt / cast(u64) width)
    Swag.print("PROBE frame ", index, " ", name, " differing ", differing, " worst ", worst,
               " macroblocks ", mbs.count, " first x ", x, " y ", y, " mb ", x / 16, ",", y / 16, " in-mb ", x % 16, ",", y % 16, "\n")
}
