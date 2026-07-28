#global namespace Hash

using Swag

public interface IHash32
{
    mtd const compute()->u32
}

// Hash a raw byte range and returns the corresponding u32
//
// Tuned for the short keys a hash table actually stores. 'Crc32' walks a lookup
// table one byte at a time below its 64 byte unrolled block, which dominates the
// cost of a table probe; this reads the buffer in 8 byte chunks, overlaps the
// tail instead of stepping through it, and never reads outside the range.
#[ConstExpr, Safety(.All, false)]
public func hashBytes32(buffer: #null const [..] u8)->u32
{
    const Mix1  = 0x9E3779B97F4A7C15'u64
    const Mix2  = 0xC2B2AE3D27D4EB4F'u64
    const Final = 0xD6E8FEB86659FD93'u64

    let length = @countof(buffer)
    var result = Mix1 ^ (length * Mix2)

    if length
    {
        let data = notnull cast(#null const [*] u8) @dataof(buffer)
        if length >= 8
        {
            var offset = 0'u64
            while length - offset >= 8
            {
                result ^= dref cast(const *u64) (data + offset)
                result *= Mix2
                result ^= result >> 29
                offset += 8
            }

            // Re-reading the last 8 bytes is cheaper than a byte loop and stays in bounds
            if offset != length
            {
                result ^= dref cast(const *u64) (data + length - 8)
                result *= Mix2
            }
        }
        elif length >= 4
        {
            let head = cast(u64) dref cast(const *u32) data
            let tail = cast(u64) dref cast(const *u32) (data + length - 4)
            result ^= head | (tail << 32)
            result *= Mix2
        }
        else
        {
            var packed = cast(u64) data[0]
            packed |= cast(u64) data[length >> 1] << 8
            packed |= cast(u64) data[length - 1] << 16
            result ^= packed
            result *= Mix2
        }
    }

    result ^= result >> 32
    result *= Final
    result ^= result >> 29
    return cast(u32) result
}

// Hash the given value and returns the corresponding u32
#[ConstExpr, Safety(.All, false)]
public func(T) hash32(value: T)->u32
{
    #static if Reflection.isString(T) do
        return hashBytes32(value orelse "")
    elif Reflection.isStruct(T) and #defined(T.IHash32) do
        #ast "return " ++ #typeof(T).fullname ++ ".IHash32.compute(value)"
    elif Reflection.isStruct(T) and #defined(T.IHash64) do
        #ast "return cast(u32) " ++ #typeof(T).fullname ++ ".IHash64.compute(value)"
    elif Reflection.isStruct(T) and #sizeof(T) == 8 do
        return cast(u32) murmur3(dref cast(const *u64) &value)
    elif Reflection.isStruct(T) and #sizeof(T) == 4 do
        return murmur3(dref cast(const *u32) &value)
    elif Reflection.isStruct(T) do
        return hashBytes32(@mkslice(cast(const [*] u8) &value, #sizeof(T)))
    elif Reflection.isInteger(T) and #sizeof(T) == 8
    {
        let hashed = cast #bit (u64) value
        let folded = cast(u32) hashed ^ cast(u32) (hashed >> 32)
        return folded * 0x9E3779B1'u32
    }
    elif Reflection.isInteger(T) and #sizeof(T) == 4 do
        return cast #bit (u32) value * 0x9E3779B1'u32
    elif Reflection.isInteger(T) do
        return cast(u32) value * 0x9E3779B1'u32
    elif #sizeof(T) == 8 do
        return cast(u32) murmur3(cast #bit (u64) value)
    elif #sizeof(T) == 4 do
        return murmur3(cast #bit (u32) value)
    else do
        return 0
}
