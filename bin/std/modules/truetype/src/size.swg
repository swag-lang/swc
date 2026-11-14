using Swag, Core

// Contains the active size and scaled face metrics.
//
// Pixel-per-em values are integers. Scales use 16.16 fixed point; all remaining
// measurements use 26.6 fixed-point pixels.
public struct SizeMetrics
{
    public readonly
    {
        xPpem:      u16     // Horizontal pixels per em.
        yPpem:      u16     // Vertical pixels per em.
        xScale:     s32     // Horizontal design-unit scale in 16.16 form.
        yScale:     s32     // Vertical design-unit scale in 16.16 form.
        ascender:   s32     // Scaled ascender above the baseline.
        descender:  s32     // Scaled descender below the baseline, usually negative.
        height:     s32     // Recommended baseline-to-baseline distance.
        maxAdvance: s32     // Maximum horizontal advance.
        capHeight:  s32     // Scaled height of an uppercase letter, or zero when the face declares none.
        xHeight:    s32     // Scaled height of a lowercase `x`, or zero when the face declares none.
    }
}

impl SizeMetrics
{
    mtd set(face: const *Face, pixelWidth, pixelHeight: u32) fail
    {
        let xScale     = try checkedScaleFixed(pixelWidth, face.unitsPerEm)
        let yScale     = try checkedScaleFixed(pixelHeight, face.unitsPerEm)
        let ascender   = try checkedScale26_6(face.ascender, pixelHeight, face.unitsPerEm)
        let descender  = try checkedScale26_6(face.descender, pixelHeight, face.unitsPerEm)
        let height     = try checkedScale26_6(face.height, pixelHeight, face.unitsPerEm)
        let maxAdvance = try checkedScale26_6(face.maxAdvanceWidth, pixelWidth, face.unitsPerEm)
        let capHeight  = try checkedScale26_6(face.capHeight, pixelHeight, face.unitsPerEm)
        let xHeight    = try checkedScale26_6(face.xHeight, pixelHeight, face.unitsPerEm)

        .xPpem      = cast(u16, pixelWidth)
        .yPpem      = cast(u16, pixelHeight)
        .xScale     = xScale
        .yScale     = yScale
        .ascender   = ascender
        .descender  = descender
        .height     = height
        .maxAdvance = maxAdvance
        .capHeight  = capHeight
        .xHeight    = xHeight
    }
}

// Associates the active metrics with their owning [[TrueType.Face]].
public struct Size
{
    public readonly
    {
        late face: *Face           // Borrowed pointer to the owning face.
        metrics:   SizeMetrics     // Metrics established by [[TrueType.Face.setPixelSize]].
    }
}

impl Size
{
    mtd initialize(face: *Face)
    {
        .face = face
    }

    mtd setPixelMetrics(pixelWidth, pixelHeight: u32) fail
    {
        try .metrics.set(.face, pixelWidth, pixelHeight)
    }
}

private func checkedRoundDiv(value, divisor: s64)->s32 fail
{
    if not divisor do
        try fault(0x17)
    var rounded: s64
    if value >= 0 do
        rounded = (value + divisor / 2) / divisor
    else do
        rounded = -(((-value) + divisor / 2) / divisor)
    if rounded < Swag.S32.Min or rounded > Swag.S32.Max do
        try fault(0x17)
    return cast(s32, rounded)
}

private func checkedScaleFixed(ppem, unitsPerEm: u32)->s32 fail =>
    try checkedRoundDiv(cast(s64, ppem) * 64 * 65536, unitsPerEm)

private func checkedScale26_6(value: s32, ppem, unitsPerEm: u32)->s32 fail =>
    try checkedRoundDiv(cast(s64, value) * cast(s64, ppem) * 64, unitsPerEm)
