#global namespace RealVideo
#global internal

using Core

struct Motion
{
    x: s32
    y: s32
}

struct Macroblock
{
    kind:    s32
    quant:   s32
    cbp:     u32
    deblock: u32
    motion:  [2][4] Motion
}

struct Plane
{
    pixels: Array'u8
    width:  s32
    height: s32
    stride: s32
}

impl Plane
{
    mtd resize(width, height: s32)
    {
        .width  = width
        .height = height
        .stride = ((width + 15) & ~15) + 64
        .pixels.resize(cast(u64, .stride) * cast(u64, (((height + 15) & ~15) + 64)))
        Memory.set(.pixels.storage(), 128, .pixels.count)
    }

    mtd at(x, y: s32)->[*] u8 => .pixels.storage() + cast(s64, ((y + 32) * .stride + x + 32))

    mtd const sample(x, y: s32)->s32
    {
        let column = Math.clamp(x, 0, .width - 1)
        let row    = Math.clamp(y, 0, .height - 1)
        return cast(s32, .pixels[(row + 32) * .stride + column + 32])
    }
}

struct Frame
{
    planes:    [3] Plane
    blocks:    Array'Macroblock
    columns:   s32
    rows:      s32
    timestamp: s32
    valid:     bool
}

impl Frame
{
    mtd resize(width, height: s32)
    {
        .valid = false
        .planes[0].resize(width, height)
        .planes[1].resize((width + 1) / 2, (height + 1) / 2)
        .planes[2].resize((width + 1) / 2, (height + 1) / 2)
        .columns = (width + 15) / 16
        .rows    = (height + 15) / 16
        .blocks.clear()
        .blocks.resize(cast(u64, (.columns * .rows)))
    }

    mtd write(target: *PlanarFrame)
    {
        target.resize(.planes[0].width, .planes[0].height)
        for channel in 3'u32
        {
            let plane  = &.planes[channel]
            let output = channel == 0 ? target.luma.storage() : (channel == 1 ? target.chromaB.storage() : target.chromaR.storage())
            for row in plane.height do
                Memory.copy(output + cast(s64, (row * plane.width)), plane.at(0, cast(s32, row)), cast(u64, plane.width))
        }
    }
}
