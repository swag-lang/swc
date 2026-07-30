using Swag, Core

// Stores an axis-aligned font-space bounding box.
//
// A face-level box uses design units. Bounds derived from a loaded outline use
// 26.6 fixed-point pixels.
public struct BBox
{
    xMin, yMin: s32     // Inclusive lower bounds.
    xMax, yMax: s32     // Inclusive upper bounds.
}

// Stores a two-dimensional point or displacement.
//
// Vectors returned from glyph operations use 26.6 fixed-point pixels unless a
// declaration says otherwise.
public struct Vector
{
    x: s32     // Horizontal component.
    y: s32     // Vertical component.
}

// Stores a 2x2 affine linear transform in 16.16 fixed-point form.
//
// The identity matrix is `{xx: 65536, yy: 65536}`.
public struct Matrix
{
    xx, xy: s32     // Coefficients that produce the transformed x coordinate.
    yx, yy: s32     // Coefficients that produce the transformed y coordinate.
}
