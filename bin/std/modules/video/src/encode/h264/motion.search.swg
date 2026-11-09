//! Format: H.264/AVC integer-pixel inter motion preselection.
//! Supported: Progressive 8-bit luma, even-pixel motion candidates and complete 16x16 macroblocks.
//! Not supported: Fractional-pixel interpolation, cropped edge macroblocks or final rate-distortion choice.
//! Role: This file cheaply screens a shifted decoded reference before quantizing its residual.
//
#global namespace H264
#global private

using Core

// Prefers one nonzero even-pixel motion candidate when sparse luma error against
// the reconstructed reference is substantially lower than zero-motion error.
// A false negative only leaves the regular zero-motion encoder path in use.
private func preferShiftedInterPrediction(current, reference: const [*] u8,
                                           width, height: s32, mbX, mbY: u32,
                                           dx, dy: s32)->bool
{
    if width <= 0 or height <= 0 or not dx and not dy or dx % 2 or dy % 2 do
        return false
    let x = cast(s32, mbX) * 16
    let y = cast(s32, mbY) * 16
    if x + 16 > width or y + 16 > height or x + dx < 0 or y + dy < 0 or
       x + dx + 16 > width or y + dy + 16 > height do
        return false
    let stride = cast(u64, width)
    let first = current[cast(u64, y) * stride + cast(u64, x)]
    // Most desktop background macroblocks are flat. Four widely spaced samples
    // reject them before comparing two reference candidates.
    if current[cast(u64, y) * stride + cast(u64, x + 15)] == first and
       current[cast(u64, y + 7) * stride + cast(u64, x + 7)] == first and
       current[cast(u64, y + 15) * stride + cast(u64, x)] == first and
       current[cast(u64, y + 15) * stride + cast(u64, x + 15)] == first do
        return false

    var zeroSad = 0'u32
    for sampleY in 4'u64
    {
        let row = (cast(u64, y) + sampleY * 4) * stride + cast(u64, x)
        for sampleX in 4'u64
        {
            let offset = row + sampleX * 4
            zeroSad += cast(u32, Math.abs(cast(s32, current[offset]) -
                                          cast(s32, reference[offset])))
        }
    }
    if zeroSad < 24 do
        return false

    var shiftedSad = 0'u32
    for sampleY in 4'u64
    {
        let sourceRow = (cast(u64, y) + sampleY * 4) * stride + cast(u64, x)
        let priorRow = (cast(u64, y + dy) + sampleY * 4) * stride + cast(u64, x + dx)
        for sampleX in 4'u64
        {
            let offset = sampleX * 4
            shiftedSad += cast(u32, Math.abs(cast(s32, current[sourceRow + offset]) -
                                             cast(s32, reference[priorRow + offset])))
            if shiftedSad * 3 >= zeroSad * 2 do
                return false
        }
    }
    return true
}
