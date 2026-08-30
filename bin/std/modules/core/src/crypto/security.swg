#global public
#global namespace Crypto

// Compares two byte sequences without data-dependent early exit.
//
// Length remains observable: sequences with different lengths return immediately.
func constantTimeEqual(left, right: const [..] u8)->bool
{
    if left.count != right.count do
        return false

    const VectorSize = #sizeof(Math.Simd.U8x16)
    let zero             = Math.Simd.splat(0'u8)
    var vectorDifference = zero
    var offset           = 0'u64
    while left.count - offset >= 4 * VectorSize
    {
        vectorDifference |= Math.Simd.load(left.buffer + offset) ^ Math.Simd.load(right.buffer + offset)
        vectorDifference |= Math.Simd.load(left.buffer + offset + VectorSize) ^ Math.Simd.load(right.buffer + offset + VectorSize)
        vectorDifference |= Math.Simd.load(left.buffer + offset + 2 * VectorSize) ^ Math.Simd.load(right.buffer + offset + 2 * VectorSize)
        vectorDifference |= Math.Simd.load(left.buffer + offset + 3 * VectorSize) ^ Math.Simd.load(right.buffer + offset + 3 * VectorSize)
        offset           += 4 * VectorSize
    }

    while left.count - offset >= VectorSize
    {
        vectorDifference |= Math.Simd.load(left.buffer + offset) ^ Math.Simd.load(right.buffer + offset)
        offset           += VectorSize
    }

    var difference = 0'u8
    while offset < left.count
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
    while done < buffer.count
    {
        let chunk = cast(u32) Math.min(buffer.count - done, cast(u64) Swag.U32.Max)
        if !randomFillNative(buffer.buffer + done, chunk) do
            fail Swag.SystemError{"the operating system cryptographic random-number generator failed"}
        done += chunk
    }
}
