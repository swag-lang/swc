#global public
#global namespace Crypto

#[Swag.Inline]
private func(T) compareEdges(left, right: const [*] u8, offset: u64)->bool
{
    let head = cast(const [*] T, left)[0] ^ cast(const [*] T, right)[0]
    let tail = cast(const [*] T, left + offset)[0] ^ cast(const [*] T, right + offset)[0]
    return (head | tail) == 0
}

// Compares two byte sequences without data-dependent early exit.
//
// Length remains observable: sequences with different lengths return immediately.
func constantTimeEqual(left, right: const [..] u8)->bool
{
    if left.count != right.count
    {
        return false
    }

    const VectorSize = #sizeof(Math.Simd.U8x16)
    let count = left.count
    if count < VectorSize
    {
        if count <= 2
        {
            if count == 2
            {
                return compareEdges!{u16}(left.buffer, right.buffer, 0)
            }

            if count
            {
                return left[0] == right[0]
            }

            return true
        }

        if count >= #sizeof(u64)
        {
            return compareEdges!{u64}(left.buffer, right.buffer, count - #sizeof(u64))
        }

        if count >= #sizeof(u32)
        {
            return compareEdges!{u32}(left.buffer, right.buffer, count - #sizeof(u32))
        }

        return compareEdges!{u16}(left.buffer, right.buffer, count - #sizeof(u16))
    }

    if count <= 4 * VectorSize
    {
        var matches = Math.Simd.load(left.buffer) == Math.Simd.load(right.buffer)
        if count == VectorSize
        {
            return Math.Simd.allTrue(matches)
        }

        let tail = count - VectorSize
        matches &= Math.Simd.load(left.buffer + tail) == Math.Simd.load(right.buffer + tail)
        if count > 2 * VectorSize
        {
            matches &= Math.Simd.load(left.buffer + VectorSize) == Math.Simd.load(right.buffer + VectorSize)
        }

        if count > 3 * VectorSize
        {
            matches &= Math.Simd.load(left.buffer + 2 * VectorSize) == Math.Simd.load(right.buffer + 2 * VectorSize)
        }

        return Math.Simd.allTrue(matches)
    }

    let zero       = Math.Simd.splat(0_u8)
    var difference = zero
    var offset     = 0_u64
    while count - offset >= 4 * VectorSize
    {
        let leftBlock  = left.buffer + offset
        let rightBlock = right.buffer + offset
        difference |= Math.Simd.load(leftBlock) ^ Math.Simd.load(rightBlock)
        difference |= Math.Simd.load(leftBlock + VectorSize) ^ Math.Simd.load(rightBlock + VectorSize)
        difference |= Math.Simd.load(leftBlock + 2 * VectorSize) ^ Math.Simd.load(rightBlock + 2 * VectorSize)
        difference |= Math.Simd.load(leftBlock + 3 * VectorSize) ^ Math.Simd.load(rightBlock + 3 * VectorSize)
        offset     += 4 * VectorSize
    }

    while count - offset >= VectorSize
    {
        difference |= Math.Simd.load(left.buffer + offset) ^ Math.Simd.load(right.buffer + offset)
        offset     += VectorSize
    }

    // Comparing an overlapping full vector covers the final partial vector.
    if offset < count
    {
        let tail = count - VectorSize
        difference |= Math.Simd.load(left.buffer + tail) ^ Math.Simd.load(right.buffer + tail)
    }

    return Math.Simd.allTrue(difference == zero)
}

// Fills `buffer` completely from the operating system cryptographic random-number source.
func randomBytes(buffer: [..] u8) fail
{
    var done = 0_u64
    while done < buffer.count
    {
        let chunk = cast(u32, Math.min(buffer.count - done, cast(u64, Swag.U32.Max)))
        if not randomFillNative(buffer.buffer + done, chunk)
        {
            fail Swag.SystemError{"the operating system cryptographic random-number generator failed"}
        }

        done += chunk
    }
}
