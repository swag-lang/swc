#global skip(test)
#global fileprivate
using Swag

#test
{
    @assert(Hash.Adler32.compute("Wikipedia") == 0x11E60398'u32)
    @assert(Hash.Crc32.compute("123456789") == 0xCBF43926'u32)
}
