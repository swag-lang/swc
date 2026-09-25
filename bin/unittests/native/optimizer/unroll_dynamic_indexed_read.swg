#global private
using Swag

#[Swag.Optimize(true)]
func hashBytes(data: const [*] u8, len: u64)->u64
{
    var hash = 2166136261'u64
    for i in len
    {
        hash ^= cast(u64) data[i]
        hash = (hash * 16777619) & 0xFFFFFFFF
    }
    return hash
}

#[Swag.Optimize(true)]
func hashBytesStrided(data: const [*] u8, len, stride: u64)->u64
{
    var hash = 2166136261'u64
    for i in len
    {
        hash ^= cast(u64) data[i * stride]
        hash = (hash * 16777619) & 0xFFFFFFFF
    }
    return hash
}

#test
{
    let data: [17] u8 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    for len in 17'u64 do
        Swag.assert(hashBytes(&data[0], len) == hashBytesStrided(&data[0], len, 1))
    Swag.assert(hashBytes(&data[0], 0) == 2166136261)
    Swag.assert(hashBytes(&data[0], 1) == 84696351)
}
