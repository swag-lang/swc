#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var guid64: Guid64
    Swag.require(Guid64.tryParse("0Xabcdef0123456789", &guid64))
    Swag.require(guid64.value == 0xABCDEF0123456789'u64)
    Swag.require(guid64.toString() == "ABCDEF0123456789")

    let expected = guid64.value
    Swag.require(not Guid64.tryParse("ABCDEF012345678", &guid64))
    Swag.require(guid64.value == expected)
    Swag.require(not Guid64.tryParse("ABCDEF012345678G", &guid64))
    Swag.require(guid64.value == expected)
}

#test
{
    var guid128 = expect Guid128.parse("00112233-4455-6677-8899-aabbccddeeff")
    let expected = guid128

    Swag.require(not Guid128.tryParse("001122334455-6677-8899-aabbccddeeff", &guid128))
    Swag.require(guid128 == expected)
    Swag.require(not Guid128.tryParse("00112233-4455-6677-8899-aabbccddeefg", &guid128))
    Swag.require(guid128 == expected)
}
