#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBuilderString(value: String, expected: string)->bool
{
    let text = value.toString()
    return value == expected and
           value.count == expected.count and
           text.count == expected.count and
           Memory.compare(text.buffer, expected.buffer, expected.count) == 0
}

#test
{
    var builder: StrConv.StringBuilder
    builder.appendString("abc")
    builder.zeroTerminate()

    Swag.require(builder.count() == 3)
    Swag.require(assertBuilderString(builder.toString(), "abc"))

    builder.zeroTerminate()
    Swag.require(builder.count() == 3)

    builder.appendString("def")
    Swag.require(builder.count() == 6)
    Swag.require(assertBuilderString(builder.moveToString(), "abcdef"))
}
