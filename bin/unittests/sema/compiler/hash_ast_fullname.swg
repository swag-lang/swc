#global private
using Swag

interface IHash32
{
    mtd const compute()->u32;
}

interface IHash64
{
    mtd const compute()->u64;
}

#[ConstExpr, Safety(.All, false)]
func(T) generatedHash32(value: T)->u32
{
    #if #defined(T.IHash32) do
        #ast "return " ++ #typeof(T).fullname ++ ".IHash32.compute(value)"
    #elif #defined(T.IHash64) do
        #ast "return cast(u32) " ++ #typeof(T).fullname ++ ".IHash64.compute(value)"
    #else do
        return 0
}

#[ConstExpr, Safety(.All, false)]
func(T) generatedHash64(value: T)->u64
{
    #if #defined(T.IHash64) do
        #ast "return " ++ #typeof(T).fullname ++ ".IHash64.compute(value)"
    #elif #defined(T.IHash32) do
        #ast "return cast(u64) " ++ #typeof(T).fullname ++ ".IHash32.compute(value)"
    #else do
        return 0
}

namespace Types
{
    struct OnlyHash32
    {
        value: u32
    }

    impl IHash32 for OnlyHash32
    {
        mtd const impl compute()->u32
        {
            return 0x1234_5678'u32 + .value
        }
    }

    struct OnlyHash64
    {
        value: u64
    }

    impl IHash64 for OnlyHash64
    {
        mtd const impl compute()->u64
        {
            return 0x0123_4567_89ab_cdef'u64 + .value
        }
    }

    struct BothHash
    {
        value: u32
    }

    impl IHash32 for BothHash
    {
        mtd const impl compute()->u32
        {
            return 0x0bad_f00d'u32 + .value
        }
    }

    impl IHash64 for BothHash
    {
        mtd const impl compute()->u64
        {
            return 0x0123_4567_dead_beef'u64 + .value
        }
    }
}

#assert(#typeof(Types.OnlyHash32).fullname == "Types.OnlyHash32")
#assert(#typeof(Types.OnlyHash64).fullname == "Types.OnlyHash64")
#assert(#typeof(Types.BothHash).fullname == "Types.BothHash")

const ONLY_HASH32 = Types.OnlyHash32{value: 3}
const ONLY_HASH64 = Types.OnlyHash64{value: 5}
const BOTH_HASH   = Types.BothHash{value: 7}

const EXPECTED_ONLY_HASH32_32 = 0x1234_567b'u32
const EXPECTED_ONLY_HASH32_64 = 0x1234_567b'u64
const EXPECTED_ONLY_HASH64_32 = 0x89ab_cdf4'u32
const EXPECTED_ONLY_HASH64_64 = 0x0123_4567_89ab_cdf4'u64
const EXPECTED_BOTH_HASH32    = 0x0bad_f014'u32
const EXPECTED_BOTH_HASH64    = 0x0123_4567_dead_bef6'u64

#assert(generatedHash32(ONLY_HASH32) == EXPECTED_ONLY_HASH32_32)
#assert(generatedHash64(ONLY_HASH32) == EXPECTED_ONLY_HASH32_64)

#assert(generatedHash32(ONLY_HASH64) == EXPECTED_ONLY_HASH64_32)
#assert(generatedHash64(ONLY_HASH64) == EXPECTED_ONLY_HASH64_64)

#assert(generatedHash32(BOTH_HASH) == EXPECTED_BOTH_HASH32)
#assert(generatedHash64(BOTH_HASH) == EXPECTED_BOTH_HASH64)
