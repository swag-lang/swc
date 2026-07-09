using Swag

// Manages a compact array of bit values.
// Bits are represented as booleans, where 'true' indicates the bit is on (1)
// and 'false' indicates the bit is off (0). This structure is memory-efficient
// for storing a large number of boolean flags.
public struct BitArray
{
    buffer:        [*] u32        // Internal buffer storing the bits packed into 32-bit integers.
    allocator:     IAllocator     // The allocator used for memory operations.
    count:         u64            // The number of bits in the array.
    capacity:      u64            // The total allocated capacity in bytes.
}

impl BitArray
{
    mtd const wordCount()->u64
    {
        if !.count do
            return 0

        var result = .count >> 5
        if result << 5 < .count do
            result += 1
        return result
    }

    // Frees the memory allocated by the bit array.
    // Does nothing if the buffer is not allocated.
    mtd free()
    {
        if !.buffer do
            return
        Memory.free(.buffer, .capacity, .allocator)
    }

    // Reallocates the private buffer to a new capacity.
    // This is a low-level memory operation.
    mtd realloc(newCapacity: u64)
    {
        if .allocator == null do
            .allocator = @getcontext().allocator
        .buffer = cast() Memory.realloc(.buffer, newCapacity, .capacity, .allocator)
    }

    mtd clearUnusedBits()
    {
        let usedBits = .count & 31
        if !usedBits do
            return

        let lastWord = .wordCount() - 1
        let mask     = (1'u32 << cast(u32) usedBits) - 1
        .buffer[lastWord] &= mask
    }
}

public impl BitArray
{
    // Returns the number of bits in the array.
    mtd const opCount()->u64
    {
        return .count
    }

    // Ensures the allocated memory is freed when the array goes out of scope.
    mtd opDrop()
    {
        .free()
    }

    // Handles the deep copy of the array when it is copied.
    // A new buffer is allocated and the content is copied over.
    mtd opPostCopy()
    {
        if .buffer
        {
            let otherBuffer = .buffer
            .buffer = null
            .reserve(.count)
            Memory.copy(.buffer, otherBuffer, .capacity)
        }
    }

    // Returns the boolean value of the bit at a specific position.
    mtd opIndex(index: u64)->bool
    {
        return .get(index)
    }

    // Sets the value of the bit at a specific position.
    mtd opIndexSet(index: u64, value: bool)
    {
        .set(index, value)
    }

    // Replaces the content of the bit array with values from a slice of booleans.
    mtd opSet(what: const [..] bool)
    {
        let len = @countof(what)
        .reserve(len)
        if !len do
            return

        Memory.set(.buffer, 0, .capacity)
        for value, index in what do
            .set(index, value)
    }

    // Compares this bit array with another one for equality.
    // Returns 'true' if both arrays have the same bit count and all bits are identical.
    mtd opEquals(other: BitArray)->bool
    {
        if .count != other.count do
            return false

        for .wordCount()
        {
            if .buffer[@index] != other.buffer[@index] do
                return false
        }

        return true
    }

    // Provides a way to iterate over each bit in the array.
    // This is a macro that accepts a code block to execute for each bit.
    // Block parameters: 'item' is the boolean value, 'index' the bit index.
    #[Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item: bool, index: u64))
    {
        #if ptr do
            #error("visiting by pointer is not supported for BitArray")
        #if back do
            #error("visiting in reverse order is not supported for BitArray")

        if !.count do
            return
        var totalWords = .count >> 5
        if totalWords << 5 < .count do
            totalWords += 1
        var countBits  = 0'u64

        #scope(Up)
        for idx in totalWords
        {
            let bitsInWord = Math.min(.count - countBits, 32'u64)
            for bitIndex in bitsInWord
            {
                #scope(Down)
                {
                    #inject(stmt, item = cast(bool) (me.buffer[idx] & (1'u32 << cast(u32) bitIndex)), index = countBits, break = break to Up, continue = break to Down)
                }

                countBits += 1
            }
        }
    }

    // Reserves capacity for a given number of bits.
    // The allocated memory is not initialized.
    mtd reserve(maxBits: u64)
    {
        if !maxBits
        {
            .free()
            .buffer = null
            .count, .capacity = 0
            return
        }

        .count    = maxBits
        .capacity = .wordCount() * 4
        .realloc(.capacity)
    }

    // Reserves capacity for a given number of bits and initializes them to a specific value.
    mtd reserve(maxBits: u64, initialValue: bool)
    {
        .reserve(maxBits)
        Memory.set(.buffer, initialValue ? 0xFF : 0x00, .capacity)
        .clearUnusedBits()
    }

    // Sets all bits in the array to the specified boolean value.
    mtd setAll(value: bool)
    {
        Memory.set(.buffer, value ? 0xFF : 0x00, .capacity)
        .clearUnusedBits()
    }

    // Sets the bit at a specific position to the specified value.
    mtd set(index: u64, value: bool)
    {
        Debug.assert(index < .count)
        let val   = index >> 5
        let bit   = index - (val << 5)
        let shift = 1'u32 << cast(u32) bit
        if value do
            .buffer[val] |= shift
        else do
            .buffer[val] &= ~shift
    }

    // Returns the boolean value of the bit at a specific position.
    mtd const get(index: u64)->bool
    {
        Debug.assert(index < .count)
        let val   = index >> 5
        let bit   = index - (val << 5)
        let shift = 1'u32 << cast(u32) bit
        return cast(bool) (.buffer[val] & shift)
    }

    // Inverts the value of the bit at a specific position.
    // Changes a 'true' bit to 'false' and a 'false' bit to 'true'.
    mtd invert(index: u64)
    {
        Debug.assert(index < .count)
        let val   = index >> 5
        let bit   = index - (val << 5)
        let shift = 1'u32 << cast(u32) bit
        if .buffer[val] & shift do
            .buffer[val] ^= shift
        else do
            .buffer[val] |= shift
    }

    // Inverts all bit values in the array.
    // Bits set to 'true' are changed to 'false', and vice versa.
    mtd invert()
    {
        if !.count do
            return
        for .wordCount() do
            .buffer[@index] = ~.buffer[@index]
        .clearUnusedBits()
    }

    // Performs a bitwise AND operation between this array and another.
    // The current array is modified to store the result. Asserts that arrays are of the same size.
    mtd andWith(other: BitArray)
    {
        Debug.assert(.count == other.count)
        if !.count do
            return
        for .wordCount() do
            .buffer[@index] &= other.buffer[@index]
        .clearUnusedBits()
    }

    // Performs a bitwise OR operation between this array and another.
    // The current array is modified to store the result. Asserts that arrays are of the same size.
    mtd orWith(other: BitArray)
    {
        Debug.assert(.count == other.count)
        if !.count do
            return
        for .wordCount() do
            .buffer[@index] |= other.buffer[@index]
        .clearUnusedBits()
    }

    // Performs a bitwise XOR operation between this array and another.
    // The current array is modified to store the result. Asserts that arrays are of the same size.
    mtd xorWith(other: BitArray)
    {
        Debug.assert(.count == other.count)
        if !.count do
            return
        for .wordCount() do
            .buffer[@index] ^= other.buffer[@index]
        .clearUnusedBits()
    }
}
