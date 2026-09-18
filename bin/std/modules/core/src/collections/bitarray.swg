using Swag

// A resizable array of bits, stored 32 to a word.
//
// Each bit reads and writes as a `bool`, where `true` is a set bit. This makes it a compact store
// for a large number of flags, and the bitwise operations work a word, or a vector of words, at a
// time.
public struct BitArray
{
    public allocator: IAllocator?     // The allocator used for memory operations.

    public readonly count: u64     // The number of bits in the array.

    private
    {
        buffer:        [*] u32?
        capacityBytes: u64
    }
}

private impl BitArray
{
    mtd const wordCount()->u64
    {
        if not .count do
            return 0

        var result = .count >> 5
        if result << 5 < .count do
            result += 1
        return result
    }

    mtd dataPtr()->[*] u32 => .buffer!

    mtd const constDataPtr()->const [*] u32 => cast(const [*] u32) .buffer!

    // Releases the storage and leaves the array empty; does nothing when nothing is allocated.
    mtd release()
    {
        if not .buffer do
            return
        Memory.free(.buffer, .capacityBytes, .allocator)
        .buffer        = null
        .count         = 0
        .capacityBytes = 0
    }

    // Reallocates the storage to `newCapacityBytes` bytes.
    mtd realloc(newCapacityBytes: u64)
    {
        if not .allocator do
            .allocator = Swag.getContext().allocator
        .buffer        = cast() Memory.realloc(.buffer, newCapacityBytes, .capacityBytes, .allocator)
        .capacityBytes = newCapacityBytes
    }

    mtd clearUnusedBits()
    {
        let usedBits = .count & 31
        if not usedBits do
            return

        let lastWord = .wordCount() - 1
        let mask     = (1'u32 << cast(u32) usedBits) - 1
        .dataPtr()[lastWord] &= mask
    }
}

public impl BitArray
{
    // Returns the number of bits in the array.
    mtd const opCount()->u64 => .count

    // Releases the storage.
    mtd opDrop()
    {
        .release()
    }

    // Gives a copied array its own storage holding the same bits.
    mtd opPostCopy()
    {
        if .buffer
        {
            let otherBuffer = .dataPtr()
            let bitCount    = .count
            let byteCount   = .capacityBytes
            .buffer        = null
            .count         = 0
            .capacityBytes = 0
            .resize(bitCount)
            Memory.copy(.dataPtr(), otherBuffer, byteCount)
        }
    }

    // Returns the bit at `index`.
    mtd const opIndex(index: u64)->bool => .get(index)

    // Sets the bit at `index` to `value`.
    mtd opIndexSet(index: u64, value: bool)
    {
        .set(index, value)
    }

    // Replaces the content with one bit per element of `values`.
    mtd opSet(values: const [..] bool)
    {
        .resize(values.count)
        for value, index in values do
            .set(index, value)
    }

    // Returns whether both arrays have the same bit count and identical bits.
    mtd const opEquals(other: BitArray)->bool
    {
        if .count != other.count do
            return false
        if not .count do
            return true

        let buffer      = .constDataPtr()
        let otherBuffer = other.constDataPtr()
        let wordCount   = .wordCount()
        const VectorWords = #sizeof(Math.Simd.U32x4) / #sizeof(u32)
        var offset = 0'u64
        while wordCount - offset >= 4 * VectorWords
        {
            if not Math.Simd.allTrue(Math.Simd.load(buffer + offset) == Math.Simd.load(otherBuffer + offset)) or
               not Math.Simd.allTrue(Math.Simd.load(buffer + offset + VectorWords) == Math.Simd.load(otherBuffer + offset + VectorWords)) or
               not Math.Simd.allTrue(Math.Simd.load(buffer + offset + 2 * VectorWords) == Math.Simd.load(otherBuffer + offset + 2 * VectorWords)) or
               not Math.Simd.allTrue(Math.Simd.load(buffer + offset + 3 * VectorWords) == Math.Simd.load(otherBuffer + offset + 3 * VectorWords)) do
                return false
            offset += 4 * VectorWords
        }

        while wordCount - offset >= VectorWords
        {
            if not Math.Simd.allTrue(Math.Simd.load(buffer + offset) == Math.Simd.load(otherBuffer + offset)) do
                return false
            offset += VectorWords
        }

        while offset < wordCount
        {
            if buffer[offset] != otherBuffer[offset] do
                return false
            offset += 1
        }

        return true
    }

    // Visits every bit in order, binding `item` to its value and `index` to its position.
    //
    // Bits are visited by value only.
    #[Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item: bool, index: u64))
        where not ptr
    {
        if not .count do
            return
        var totalWords = .count >> 5
        if totalWords << 5 < .count do
            totalWords += 1
        var countBits = 0'u64
        let buffer    = .buffer!

        #scope(Up)
        for idx in totalWords
        {
            let bitsInWord = Math.min(.count - countBits, 32'u64)
            for bitIndex in bitsInWord
            {
                #scope(Down)
                {
                    #inject(stmt, item = cast(bool) (buffer[idx] & (1'u32 << cast(u32) bitIndex)), index = countBits, break = break to Up, continue = break to Down)
                }

                countBits += 1
            }
        }
    }

    // Sets the number of bits to `bitCount` and every bit to `initialValue`.
    //
    // The previous bits are not preserved. A zero `bitCount` releases the storage.
    mtd resize(bitCount: u64, initialValue = false)
    {
        if not bitCount
        {
            .release()
            return
        }

        .count = bitCount
        let byteCount = .wordCount() * #sizeof(u32)
        if byteCount != .capacityBytes do
            .realloc(byteCount)
        Memory.set(.dataPtr(), initialValue ? 0xFF : 0x00, .capacityBytes)
        .clearUnusedBits()
    }

    // Sets every bit to `value`.
    mtd setAll(value: bool)
    {
        if not .count do
            return
        Memory.set(.dataPtr(), value ? 0xFF : 0x00, .capacityBytes)
        .clearUnusedBits()
    }

    // Sets the bit at `index` to `value`.
    mtd set(index: u64, value: bool)
    {
        Swag.assert(index < .count)
        let val    = index >> 5
        let bit    = index - (val << 5)
        let shift  = 1'u32 << cast(u32) bit
        let buffer = .dataPtr()
        if value do
            buffer[val] |= shift
        else do
            buffer[val] &= ~shift
    }

    // Returns the bit at `index`.
    mtd const get(index: u64)->bool
    {
        Swag.assert(index < .count)
        let val   = index >> 5
        let bit   = index - (val << 5)
        let shift = 1'u32 << cast(u32) bit
        return cast(bool) (.constDataPtr()[val] & shift)
    }

    // Inverts the bit at `index`.
    mtd invert(index: u64)
    {
        Swag.assert(index < .count)
        let val    = index >> 5
        let bit    = index - (val << 5)
        let shift  = 1'u32 << cast(u32) bit
        let buffer = .dataPtr()
        buffer[val] ^= shift
    }

    // Inverts every bit.
    mtd invert()
    {
        if not .count do
            return
        const VectorWords = #sizeof(Math.Simd.U32x4) / #sizeof(u32)
        let buffer = .dataPtr()
        let words  = .wordCount()
        var index  = 0'u64
        while words - index >= VectorWords
        {
            Math.Simd.store(buffer + index, ~Math.Simd.load(buffer + index))
            index += VectorWords
        }

        while index < words
        {
            buffer[index] = ~buffer[index]
            index         += 1
        }

        .clearUnusedBits()
    }

    // Replaces every bit with its AND with the bit at the same index in `other`.
    //
    // Both arrays must have the same bit count.
    mtd andWith(other: BitArray)
    {
        Swag.assert(.count == other.count)
        if not .count do
            return
        let buffer      = .dataPtr()
        let otherBuffer = other.constDataPtr()
        const VectorWords = #sizeof(Math.Simd.U32x4) / #sizeof(u32)
        let words = .wordCount()
        var index = 0'u64
        while words - index >= VectorWords
        {
            Math.Simd.store(buffer + index, Math.Simd.load(buffer + index) & Math.Simd.load(otherBuffer + index))
            index += VectorWords
        }

        while index < words
        {
            buffer[index] &= otherBuffer[index]
            index         += 1
        }

        .clearUnusedBits()
    }

    // Replaces every bit with its OR with the bit at the same index in `other`.
    //
    // Both arrays must have the same bit count.
    mtd orWith(other: BitArray)
    {
        Swag.assert(.count == other.count)
        if not .count do
            return
        let buffer      = .dataPtr()
        let otherBuffer = other.constDataPtr()
        const VectorWords = #sizeof(Math.Simd.U32x4) / #sizeof(u32)
        let words = .wordCount()
        var index = 0'u64
        while words - index >= VectorWords
        {
            Math.Simd.store(buffer + index, Math.Simd.load(buffer + index) | Math.Simd.load(otherBuffer + index))
            index += VectorWords
        }

        while index < words
        {
            buffer[index] |= otherBuffer[index]
            index         += 1
        }

        .clearUnusedBits()
    }

    // Replaces every bit with its XOR with the bit at the same index in `other`.
    //
    // Both arrays must have the same bit count.
    mtd xorWith(other: BitArray)
    {
        Swag.assert(.count == other.count)
        if not .count do
            return
        let buffer      = .dataPtr()
        let otherBuffer = other.constDataPtr()
        const VectorWords = #sizeof(Math.Simd.U32x4) / #sizeof(u32)
        let words = .wordCount()
        var index = 0'u64
        while words - index >= VectorWords
        {
            Math.Simd.store(buffer + index, Math.Simd.load(buffer + index) ^ Math.Simd.load(otherBuffer + index))
            index += VectorWords
        }

        while index < words
        {
            buffer[index] ^= otherBuffer[index]
            index         += 1
        }

        .clearUnusedBits()
    }
}
