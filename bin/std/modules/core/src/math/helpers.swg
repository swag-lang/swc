#global public
#global namespace Math

using Swag

// Clamp a value between a lower and upper bound.
// Returns 'low' if 'x' < 'low', 'up' if 'x' > 'up', otherwise returns 'x'.
#[ConstExpr, Inline]
func(T) clamp(x, low, up: T)->T => Swag.max(Swag.min(x, up), low)

#[ConstExpr, Inline]
{
    // Return the smaller of two values.
    // Generic implementation that works with any comparable type 'T'.
    func(T) min(x, y: T)->T => Swag.min(x, y)

    // Return the larger of two values.
    // Generic implementation that works with any comparable type 'T'.
    func(T) max(x, y: T)->T => Swag.max(x, y)

    // Return the smallest of three values.
    // Efficiently finds the minimum using nested comparisons.
    func(T) min(x, y, z: T)->T => Swag.min(Swag.min(x, y), z)

    // Return the largest of three values.
    // Efficiently finds the maximum using nested comparisons.
    func(T) max(x, y, z: T)->T => Swag.max(Swag.max(x, y), z)

    // Return the smallest of four values.
    // Efficiently finds the minimum using nested comparisons.
    func(T) min(x, y, z, w: T)->T => Swag.min(Swag.min(Swag.min(x, y), z), w)

    // Return the largest of four values.
    // Efficiently finds the maximum using nested comparisons.
    func(T) max(x, y, z, w: T)->T => Swag.max(Swag.max(Swag.max(x, y), z), w)
}

// Convert a big-endian integer to the current architecture's native format.
// On big-endian systems returns 'x' unchanged, on little-endian systems performs byte swap.
#[ConstExpr, Inline]
func(T) bigEndianToNative(x: T)->T
{
    #static if BIG_ENDIAN do
        return x
    else do
        return Math.byteswap(x)
}

// Convert a native architecture integer to big-endian format.
// On big-endian systems returns 'x' unchanged, on little-endian systems performs byte swap.
#[ConstExpr, Inline]
func(T) nativeToBigEndian(x: T)->T
{
    #static if BIG_ENDIAN do
        return x
    else do
        return Math.byteswap(x)
}

// Convert a little-endian integer to the current architecture's native format.
// On little-endian systems returns 'x' unchanged, on big-endian systems performs byte swap.
#[ConstExpr, Inline]
func(T) littleEndianToNative(x: T)->T
{
    #static if BIG_ENDIAN do
        return Math.byteswap(x)
    else do
        return x
}

// Convert a native architecture integer to little-endian format.
// On little-endian systems returns 'x' unchanged, on big-endian systems performs byte swap.
#[ConstExpr, Inline]
func(T) nativeToLittleEndian(x: T)->T
{
    #static if BIG_ENDIAN do
        return Math.byteswap(x)
    else do
        return x
}
