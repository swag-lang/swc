#global if #command == Swag.CompilerCommand.Test

using Core

// The runtime keeps a tiny conversion on the caller without starting unused workers.
#test
{
    let scheduler = Swag.schedulerInstance()
    let started   = scheduler.started.load()
    var storage: Array'u8
    let view      = flatPlanarPicture(&storage, 8, 1, 100, 90, 200)
    var image:   Image
    view.convertToRgb(&image)
    Swag.assert(image.pixelColor(7, 0) == expectedPlanarColor(100, 90, 200))
    Swag.assert(scheduler.started.load() == started)
}

// Odd, padded planes exercise SIMD, scalar pairs, the last pixel and the last row across
// every matrix and range. Reusing one target must join every writer before returning.
#[Swag.TestTag("parallel")]
#test
{
    Swag.setWorkerCount(4)
    const Width        = 259
    const Height       = 131
    const LumaStride   = 267'u64
    const ChromaStride = 137'u64
    const LumaSize     = LumaStride * Height
    const ChromaSize   = ChromaStride * ((Height + 1) / 2)
    var storage: Array'u8
    storage.resize(LumaSize + ChromaSize * 2)
    for index in storage.count do
        storage[index] = cast(u8) ((index * 37 + index / 97) & 255)
    var view = Yuv420View{luma: storage.buffer!, chromaB: storage.buffer! + LumaSize, chromaR: storage.buffer! + LumaSize + ChromaSize, lumaStride: LumaStride, chromaStride: ChromaStride, width: Width, height: Height}
    let matrices: [3] YuvMatrix = [.Bt601, .Bt709, .Bt2020]
    var image:    Image
    for matrix in matrices
    {
        view.matrix = matrix
        for range in 2
        {
            view.studioRange = range == 0
            for repeat in 3
            {
                view.convertToRgb(&image)
                for y in Height
                {
                    for x in Width
                    {
                        let chromaAt = cast(u64) (y / 2) * ChromaStride + cast(u64) (x / 2)
                        let expected = expectedPlanarColor(view.luma[cast(u64) y * LumaStride + cast(u64) x], view.chromaB[chromaAt], view.chromaR[chromaAt], matrix, view.studioRange)
                        Swag.assert(image.pixelColor(x, y) == expected)
                    }
                }
            }
        }
    }
}
