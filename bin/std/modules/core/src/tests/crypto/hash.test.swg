#global skip(test)
#global fileprivate
using Swag

#test
{
    @assert(Hash.Adler32.compute("Wikipedia") == 0x11E60398'u32)
    @assert(Hash.Crc32.compute("123456789") == 0xCBF43926'u32)
    @assert(Hash.Crc64.compute("123456789") == 0x6C40_DF5F_0B49_7347'u64)
    @assert(Hash.Crc64.compute("123456789", Hash.Crc64Kind.ISOXZ) == 0x995D_C9BB_DF19_39FA'u64)

    @assert(Hash.Md5.toString(Hash.Md5.compute("")) == "D41D8CD98F00B204E9800998ECF8427E")
    @assert(Hash.Md5.toString(Hash.Md5.compute("abc")) == "900150983CD24FB0D6963F7D28E17F72")

    let sha1 = Hash.Sha1.compute("abc")
    @assert(sha1[0] == 0xA9993E36'u32)
    @assert(sha1[1] == 0x4706816A'u32)
    @assert(sha1[2] == 0xBA3E2571'u32)
    @assert(sha1[3] == 0x7850C26C'u32)
    @assert(sha1[4] == 0x9CD0D89D'u32)

    let sha256 = Hash.Sha256.compute("abc")
    @assert(sha256[0] == 0xBA7816BF'u32)
    @assert(sha256[1] == 0x8F01CFEA'u32)
    @assert(sha256[2] == 0x414140DE'u32)
    @assert(sha256[3] == 0x5DAE2223'u32)
    @assert(sha256[4] == 0xB00361A3'u32)
    @assert(sha256[5] == 0x96177A9C'u32)
    @assert(sha256[6] == 0xB410FF61'u32)
    @assert(sha256[7] == 0xF20015AD'u32)
}
