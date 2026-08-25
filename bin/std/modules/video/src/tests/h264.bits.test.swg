#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func referenceUnescapeRbsp(data: const [..] u8)->Array'u8
{
    var result: retval
    var zeros = 0'u32
    for value in data
    {
        if zeros >= 2 and value == 3
        {
            zeros = 0
            continue
        }

        zeros = value == 0 ? zeros + 1 : 0
        result.add(value)
    }

    return result
}

func assertRbspUnescape(data: const [..] u8)
{
    let expected = referenceUnescapeRbsp(data)
    var actual: Array'u8
    unescapeRbsp(&actual, data)
    @assert(actual.count == expected.count)
    @assert(!actual.count or Memory.compare(actual.buffer!, expected.buffer!, actual.count) == 0)
}

// Exercise every vector alignment and tail, with the escape triplet at every possible byte.
#test
{
    for alignment in 16'u64
    {
        for length in 81'u64
        {
            var storage: Array'u8
            storage.resize(alignment + length + 1)
            let data = storage.toSlice()[alignment until alignment + length]
            for index in length do
                data[index] = cast(u8) ((index * 37 + 11) & 255)
            assertRbspUnescape(data)

            for escape in 2'u64 until length
            {
                data[escape - 2] = 0
                data[escape - 1] = 0
                data[escape]     = 3
                assertRbspUnescape(data)
                data[escape - 2] = 17
                data[escape - 1] = 29
                data[escape]     = 43
            }
        }
    }

    const Repeated = [0'u8, 0, 3, 0, 0, 3, 0, 0, 0, 3, 1]
    assertRbspUnescape(Repeated)
}
