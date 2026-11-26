#global private

using Core

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func mprotect(address: *void, length: u64, protection: s32)->s32

const TestSizes = [
    {size: 2047'u64, hex: "58830fbf51a4423c573b164471690570e544cfe793bead46225664796b4b1467"},
    {size: 2048'u64, hex: "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a"},
    {size: 2049'u64, hex: "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030"},
    {size: 3071'u64, hex: "38955dc63aa8e2f7af9e3abf3be7435d91814bb0a511df7f0dd465dfcc6d7275"},
    {size: 3072'u64, hex: "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2"},
    {size: 3073'u64, hex: "7124b49501012f81cc7f11ca069ec9226cecb8a2c850cfe644e327d22d3e1cd3"},
    {size: 4095'u64, hex: "0cdbdde4d038f0509412a5d1c3b1fb767d5e8c8a0eb2aae963fd36d1f544791a"},
    {size: 4096'u64, hex: "015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969"},
    {size: 4097'u64, hex: "9b4052b38f1c5fc8b1f9ff7ac7b27cd242487b3d890d15c96a1c25b8aa0fb995"},
    {size: 6144'u64, hex: "3e2e5b74e048f3add6d21faab3f83aa44d3b2278afb83b80b3c35164ebeca205"},
    {size: 7168'u64, hex: "61da957ec2499a95d6b8023e2b0e604ec7f6b50e80a9678b89d2628e99ada77a"},
    {size: 7169'u64, hex: "a003fc7a51754a9b3c7fae0367ab3d782dccf28855a03d435f8cfe74605e7817"},
    {size: 8191'u64, hex: "bae8dc916e8643c6cf024097237cde1cba35c05b5d84c02834cb6b886edb76d9"},
    {size: 8192'u64, hex: "aae792484c8efe4f19e2ca7d371d8c467ffb10748d8a5a1ae579948f718a2a63"},
    {size: 8193'u64, hex: "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b"},
    {size: 12287'u64, hex: "0f0123d338c415c06a80d19c0ad9d73f04924a08f086a56959d19ed74875bab0"}]

func nibble(value: u8)->u8
{
    return value <= '9' ? value - '0' : value - 'a' + 10
}

#main
{
    const PageSize = 4096'u64
    const Usable   = 3 * PageSize
    const Mapping  = Usable + 2 * PageSize
    let region = Linux.mmap(null, Mapping, Linux.PROT_NONE, Linux.MAP_PRIVATE | Linux.MAP_ANONYMOUS, -1, 0)
    Swag.require(region != null and cast(u64, region) != Swag.U64.Max)
    let base = cast([*] u8, region) + PageSize
    defer Swag.require(Linux.munmap(region, Mapping) == 0)

    for sample in TestSizes
    {
        for side in 2
        {
            Swag.require(mprotect(base, Usable, Linux.PROT_READ | Linux.PROT_WRITE) == 0)
            let start = side == 0 ? base : base + Usable - sample.size
            for index in sample.size do
                start[index] = cast(u8, index % 251)
            Swag.require(mprotect(base, Usable, Linux.PROT_READ) == 0)

            let data = Swag.makeSlice(start, sample.size)
            var actual: [32] u8
            var expected: [32] u8
            for index in expected.count do
                expected[index] = cast(u8, (nibble(sample.hex[2 * index]) << 4) | nibble(sample.hex[2 * index + 1]))

            expect Hash.Blake3.compute(data, actual)
            Swag.require(Crypto.constantTimeEqual(actual, expected))

            let split = sample.size < 3073 ? Math.min(2048, sample.size) : 3072
            var stream = Hash.Blake3.create()
            stream.update(data[until split])
            stream.update(data[split to])
            expect stream.finalize(actual)
            Swag.require(Crypto.constantTimeEqual(actual, expected))
        }
    }
}
