using Swag, Core

// Contains the active size and scaled face metrics.
//
// Pixel-per-em values are integers. Scales use 16.16 fixed point; all remaining
// measurements use 26.6 fixed-point pixels.
public struct SizeMetrics
{
    xPpem:      u16 // Horizontal pixels per em.
    yPpem:      u16 // Vertical pixels per em.
    xScale:     s32 // Horizontal design-unit scale in 16.16 form.
    yScale:     s32 // Vertical design-unit scale in 16.16 form.
    ascender:   s32 // Scaled ascender above the baseline.
    descender:  s32 // Scaled descender below the baseline, usually negative.
    height:     s32 // Recommended baseline-to-baseline distance.
    maxAdvance: s32 // Maximum horizontal advance.
}

// Associates the active metrics with their owning [[TrueType.Face]].
public struct Size
{
    #[Swag.Late]
    face:    *Face       // Borrowed pointer to the owning face.
    metrics: SizeMetrics // Metrics established by [[TrueType.Face.setPixelSize]].
}
