#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func scryptStressHexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func scryptStressHexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((scryptStressHexDigit(text[index]) << 4) | scryptStressHexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

#[Swag.TestTag("stress")]
#test
{
    let expected = scryptStressHexBytes("fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640")
    var output: [64] u8
    expect Crypto.scrypt("password", "NaCl", 1024, 8, 16, 32 * 1024 * 1024, output)
    Swag.require(Crypto.constantTimeEqual(output, expected.toSlice()))
}
