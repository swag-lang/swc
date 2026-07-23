using Swag, Core

public struct SizeMetrics
{
    xPpem:          u16
    yPpem:          u16
    xScale:         s32
    yScale:         s32
    ascender:       s32
    descender:      s32
    height:         s32
    maxAdvance:     s32
}

public struct Size
{
    face:      #late *Face
    metrics:   SizeMetrics
}
