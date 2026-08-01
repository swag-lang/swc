using Swag, Core

// Contains the active size and scaled face metrics.
//
// Pixel-per-em values are integers. Scales use 16.16 fixed point; all remaining
// measurements use 26.6 fixed-point pixels.
public struct SizeMetrics
{
    readonly
    {
        xPpem:      u16     // Horizontal pixels per em.
        yPpem:      u16     // Vertical pixels per em.
        xScale:     s32     // Horizontal design-unit scale in 16.16 form.
        yScale:     s32     // Vertical design-unit scale in 16.16 form.
        ascender:   s32     // Scaled ascender above the baseline.
        descender:  s32     // Scaled descender below the baseline, usually negative.
        height:     s32     // Recommended baseline-to-baseline distance.
        maxAdvance: s32     // Maximum horizontal advance.
    }
}

impl SizeMetrics
{
    internal mtd set(face: const *Face, pixelWidth, pixelHeight: u32)
    {
        .xPpem      = cast(u16) pixelWidth
        .yPpem      = cast(u16) pixelHeight
        .xScale     = scaleFixed(pixelWidth, face.unitsPerEm)
        .yScale     = scaleFixed(pixelHeight, face.unitsPerEm)
        .ascender   = scale26_6(face.ascender, pixelHeight, face.unitsPerEm)
        .descender  = scale26_6(face.descender, pixelHeight, face.unitsPerEm)
        .height     = scale26_6(face.height, pixelHeight, face.unitsPerEm)
        .maxAdvance = scale26_6(face.maxAdvanceWidth, pixelWidth, face.unitsPerEm)
    }
}

// Associates the active metrics with their owning [[TrueType.Face]].
public struct Size
{
    readonly
    {
        #[Swag.Late]
        face:    *Face           // Borrowed pointer to the owning face.
        metrics: SizeMetrics     // Metrics established by [[TrueType.Face.setPixelSize]].
    }
}

impl Size
{
    internal mtd initialize(face: *Face)
    {
        .face = face
    }

    internal mtd setPixelMetrics(pixelWidth, pixelHeight: u32)
    {
        .metrics.set(.face, pixelWidth, pixelHeight)
    }
}
