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
    Swag.require(image.pixelColor(7, 0) == expectedPlanarColor(100, 90, 200))
    Swag.require(scheduler.started.load() == started)
}

// Odd, padded planes exercise SIMD, scalar tails, the last pixel and the last row across
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
        storage[index] = cast(u8, ((index * 37 + index / 97) & 255))
    var view = YuvPlanarView{luma: storage.storage(), chromaB: storage.storage() + LumaSize, chromaR: storage.storage() + LumaSize + ChromaSize, lumaStride: LumaStride, chromaStride: ChromaStride, width: Width, height: Height}
    let matrices: [3] YuvMatrix = [.Bt601, .Bt709, .Bt2020]
    var image:    Image
    for matrix in matrices
    {
        view.matrix = matrix
        for range in 2
        {
            view.studioRange = range == 0
            for 3
            {
                view.convertToRgb(&image)
                for y in Height
                {
                    for x in Width
                    {
                        let cb       = expectedChromaSample(view.chromaB, ChromaStride, (Width + 1) / 2, (Height + 1) / 2, Width, Height, x, y)
                        let cr       = expectedChromaSample(view.chromaR, ChromaStride, (Width + 1) / 2, (Height + 1) / 2, Width, Height, x, y)
                        let expected = expectedPlanarColor(view.luma[cast(u64, y) * LumaStride + cast(u64, x)], cb, cr, matrix, view.studioRange)
                        Swag.require(image.pixelColor(x, y) == expected)
                    }
                }
            }
        }
    }
}

// Even subsampled planes use quarter-texel weights and round only the final sample.
#test
{
    const Widths:   [4] s32       = [16, 34, 48, 66]
    const Heights:  [2] s32       = [2, 10]
    const Matrices: [3] YuvMatrix = [.Bt601, .Bt709, .Bt2020]
    var storage: Array'u8
    var result:  Image
    for width in Widths
    {
        for height in Heights
        {
            let lumaStride   = cast(u64, width + 3)
            let chromaStride = cast(u64, width / 2 + 5)
            let lumaSize     = lumaStride * cast(u64, height)
            let chromaSize   = chromaStride * cast(u64, height / 2)
            storage.resize(lumaSize + chromaSize * 2)
            for index in storage.count do
                storage[index] = cast(u8, ((index * 67 + index / 47) & 255))

            var view = YuvPlanarView{luma: storage.storage(), chromaB: storage.storage() + lumaSize,
                                     chromaR: storage.storage() + lumaSize + chromaSize, lumaStride: lumaStride,
                                     chromaStride: chromaStride, width: width, height: height}
            for matrix in Matrices
            {
                view.matrix = matrix
                for range in 2
                {
                    view.studioRange = range == 0
                    view.convertToRgb(&result)
                    for y in height
                    {
                        for x in width
                        {
                            let cb    = expectedChromaSample(view.chromaB, chromaStride, width / 2, height / 2, width, height, x, y)
                            let cr    = expectedChromaSample(view.chromaR, chromaStride, width / 2, height / 2, width, height, x, y)
                            let value = view.luma[cast(u64, y) * lumaStride + cast(u64, x)]
                            Swag.require(result.pixelColor(x, y) == expectedPlanarColor(value, cb, cr, matrix, view.studioRange))
                        }
                    }
                }
            }
        }
    }
}
