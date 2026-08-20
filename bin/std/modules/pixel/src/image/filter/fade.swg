using Core

public impl Image
{
    // Fade to a given color. 'factor' is [0, 1]
    mtd fade(color: Color, factor: f32 = 0.5)
    {
        // unsupported pixel format
        if .pixelFormat.channels() < 3 or .pixelFormat.bitDepth() != 8 do
            return

        var convArrR: [256] u8 = undefined
        var convArrG: [256] u8 = undefined
        var convArrB: [256] u8 = undefined

        if .pixelFormat == .BGR8 or .pixelFormat == .BGRA8
        {
            for i in 256
            {
                convArrR[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.b, factor)
                convArrG[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.g, factor)
                convArrB[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.r, factor)
            }
        }
        elif .pixelFormat == .RGB8 or .pixelFormat == .RGBA8
        {
            for i in 256
            {
                convArrR[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.r, factor)
                convArrG[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.g, factor)
                convArrB[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.b, factor)
            }
        }

        .applyColorLuts(&convArrR[0], &convArrG[0], &convArrB[0])
    }
}
