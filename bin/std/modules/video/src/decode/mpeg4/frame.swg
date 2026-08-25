//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns picture storage, edge extension, and planar export.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors

// Samples kept around each plane so an unrestricted motion vector still reads inside it.
//
// The format lets a vector point up to sixteen samples outside the picture, and half-sample
// interpolation reads one sample further, so the edge is replicated far enough that motion
// compensation never has to test a coordinate.
const FramePadding = 32'u32

// One decoded picture: 4:2:0 planes with replicated edges.
#[Swag.NoCopy]
struct Frame
{
    luma:         Array'u8
    chromaB:      Array'u8
    chromaR:      Array'u8
    strideLuma:   u64
    strideChroma: u64
    width:        u32     // Coded luma width, a multiple of sixteen.
    height:       u32
    displayWidth: u32     // What the layer says is visible.
    displayHeight:u32
    inUse:        bool    // The picture is a reference or is waiting for its display turn.
}

impl Frame
{
    // Sizes the planes for one layer geometry, keeping what is already the right size.
    mtd prepare(codedWidth, codedHeight, visibleWidth, visibleHeight: u32)
    {
        let strideLuma   = cast(u64) (codedWidth + 2 * FramePadding)
        let strideChroma = cast(u64) (codedWidth / 2 + 2 * FramePadding)
        let rowsLuma     = cast(u64) (codedHeight + 2 * FramePadding)
        let rowsChroma   = cast(u64) (codedHeight / 2 + 2 * FramePadding)

        if .strideLuma != strideLuma or .luma.count != strideLuma * rowsLuma
        {
            .luma.resize(strideLuma * rowsLuma)
            .chromaB.resize(strideChroma * rowsChroma)
            .chromaR.resize(strideChroma * rowsChroma)
            Memory.set(.luma.buffer!, 0, .luma.count)
            Memory.set(.chromaB.buffer!, 128, .chromaB.count)
            Memory.set(.chromaR.buffer!, 128, .chromaR.count)
        }

        .strideLuma    = strideLuma
        .strideChroma  = strideChroma
        .width         = codedWidth
        .height        = codedHeight
        .displayWidth  = visibleWidth
        .displayHeight = visibleHeight
    }

    // The first sample of the picture inside its padded plane.
    mtd const lumaOrigin()->u64 => cast(u64) FramePadding * .strideLuma + cast(u64) FramePadding
    mtd const chromaOrigin()->u64 => cast(u64) FramePadding * .strideChroma + cast(u64) FramePadding

    // Replicates the border of every plane into the padding.
    //
    // Motion compensation reads through the padding rather than clamping each coordinate, so the
    // padding has to hold what a clamp would have produced.
    mtd extendEdges()
    {
        .extendPlane(.luma.buffer!, .strideLuma, .width, .height)
        .extendPlane(.chromaB.buffer!, .strideChroma, .width / 2, .height / 2)
        .extendPlane(.chromaR.buffer!, .strideChroma, .width / 2, .height / 2)
    }

    private mtd extendPlane(plane: [*] u8, stride: u64, width, height: u32)
    {
        let pad    = cast(u64) FramePadding
        let origin = pad * stride + pad

        // Left and right of every row.
        for y in cast(u64) height
        {
            let row   = origin + y * stride
            let first = plane[row]
            let last  = plane[row + cast(u64) width - 1]
            Memory.set(plane + row - pad, first, pad)
            Memory.set(plane + row + cast(u64) width, last, pad)
        }

        // Whole rows above and below, which now include the corners.
        let top    = origin - pad
        let bottom = origin + (cast(u64) height - 1) * stride - pad
        for y in pad
        {
            Memory.copy(plane + top - (y + 1) * stride, plane + top, stride)
            Memory.copy(plane + bottom + (y + 1) * stride, plane + bottom, stride)
        }
    }

    // Hands the visible picture over as three tightly packed planes.
    mtd const writePlanar(target: *PlanarFrame)
    {
        let width  = cast(s32) .displayWidth
        let height = cast(s32) .displayHeight
        let chromaWidth  = cast(u64) ((width + 1) / 2)
        let chromaHeight = cast(u64) ((height + 1) / 2)

        target.width        = width
        target.height       = height
        target.strideLuma   = cast(u32) width
        target.strideChroma = cast(u32) chromaWidth
        target.studioRange  = true
        target.luma.resize(cast(u64) width * cast(u64) height)
        target.chromaB.resize(chromaWidth * chromaHeight)
        target.chromaR.resize(chromaWidth * chromaHeight)

        let lumaAt = .lumaOrigin()
        for y in cast(u64) height do
            Memory.copy(target.luma.buffer! + y * cast(u64) width, .luma.buffer! + lumaAt + y * .strideLuma, cast(u64) width)

        let chromaAt = .chromaOrigin()
        for y in chromaHeight
        {
            Memory.copy(target.chromaB.buffer! + y * chromaWidth, .chromaB.buffer! + chromaAt + y * .strideChroma, chromaWidth)
            Memory.copy(target.chromaR.buffer! + y * chromaWidth, .chromaR.buffer! + chromaAt + y * .strideChroma, chromaWidth)
        }
    }
}
