#global public
#global namespace Crypto

// Compares two byte sequences without data-dependent early exit.
//
// Length remains observable: sequences with different lengths return immediately.
func constantTimeEqual(left, right: const [..] u8)->bool
{
    if @countof(left) != @countof(right) do
        return false

    const VectorSize = #sizeof(Math.Simd.U8x16)
    let zero             = Math.Simd.splat(0'u8)
    var vectorDifference = zero
    var offset           = 0'u64
    while @countof(left) - offset >= 4 * VectorSize
    {
        vectorDifference |= Math.Simd.load(@dataof(left) + offset) ^ Math.Simd.load(@dataof(right) + offset)
        vectorDifference |= Math.Simd.load(@dataof(left) + offset + VectorSize) ^ Math.Simd.load(@dataof(right) + offset + VectorSize)
        vectorDifference |= Math.Simd.load(@dataof(left) + offset + 2 * VectorSize) ^ Math.Simd.load(@dataof(right) + offset + 2 * VectorSize)
        vectorDifference |= Math.Simd.load(@dataof(left) + offset + 3 * VectorSize) ^ Math.Simd.load(@dataof(right) + offset + 3 * VectorSize)
        offset           += 4 * VectorSize
    }

    while @countof(left) - offset >= VectorSize
    {
        vectorDifference |= Math.Simd.load(@dataof(left) + offset) ^ Math.Simd.load(@dataof(right) + offset)
        offset           += VectorSize
    }

    var difference = 0'u8
    while offset < @countof(left)
    {
        difference |= left[offset] ^ right[offset]
        offset     += 1
    }

    return difference == 0 and !Math.Simd.anyTrue(vectorDifference != zero)
}

// Fills `buffer` completely from the operating system cryptographic random-number source.
func randomBytes(buffer: [..] u8) fail
{
    var done = 0'u64
    while done < @countof(buffer)
    {
        let chunk = cast(u32) Math.min(@countof(buffer) - done, cast(u64) Swag.U32.Max)
        if !randomFillNative(@dataof(buffer) + done, chunk) do
            fail Swag.SystemError{"the operating system cryptographic random-number generator failed"}
        done += chunk
    }
}
