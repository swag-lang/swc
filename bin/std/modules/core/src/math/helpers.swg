#global public
#global namespace Math

using Swag

// Returns `x` clamped to the range [`low`, `up`].
//
// `low` wins when it is greater than `up`.
#[ConstExpr, Inline]
func(T) clamp(x, low, up: T)->T => Swag.max(Swag.min(x, up), low)

#[ConstExpr, Inline]
{
    // Returns the smaller of `x` and `y`.
    func(T) min(x, y: T)->T => Swag.min(x, y)

    // Returns the larger of `x` and `y`.
    func(T) max(x, y: T)->T => Swag.max(x, y)

    // Returns the smallest of `x`, `y`, and `z`.
    func(T) min(x, y, z: T)->T => Swag.min(Swag.min(x, y), z)

    // Returns the largest of `x`, `y`, and `z`.
    func(T) max(x, y, z: T)->T => Swag.max(Swag.max(x, y), z)

    // Returns the smallest of `x`, `y`, `z`, and `w`.
    func(T) min(x, y, z, w: T)->T => Swag.min(Swag.min(Swag.min(x, y), z), w)

    // Returns the largest of `x`, `y`, `z`, and `w`.
    func(T) max(x, y, z, w: T)->T => Swag.max(Swag.max(Swag.max(x, y), z), w)
}

// Returns the big-endian integer `x` in the byte order of the target.
//
// The value is returned unchanged on a big-endian target and byte-swapped otherwise.
#[ConstExpr, Inline]
func(T) bigEndianToNative(x: T)->T
{
    #static if BIG_ENDIAN do
        return x
    else do
        return Math.byteswap(x)
}

// Returns the integer `x`, in the byte order of the target, as big-endian.
//
// The value is returned unchanged on a big-endian target and byte-swapped otherwise.
#[ConstExpr, Inline]
func(T) nativeToBigEndian(x: T)->T
{
    #static if BIG_ENDIAN do
        return x
    else do
        return Math.byteswap(x)
}

// Returns the little-endian integer `x` in the byte order of the target.
//
// The value is returned unchanged on a little-endian target and byte-swapped otherwise.
#[ConstExpr, Inline]
func(T) littleEndianToNative(x: T)->T
{
    #static if BIG_ENDIAN do
        return Math.byteswap(x)
    else do
        return x
}

// Returns the integer `x`, in the byte order of the target, as little-endian.
//
// The value is returned unchanged on a little-endian target and byte-swapped otherwise.
#[ConstExpr, Inline]
func(T) nativeToLittleEndian(x: T)->T
{
    #static if BIG_ENDIAN do
        return Math.byteswap(x)
    else do
        return x
}
