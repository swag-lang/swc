#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertBuilderString(value: const &String, expected: string)->bool
{
    let text = value.toString()
    return value == expected and
        @countof(value) == @countof(expected) and
        @countof(text) == @countof(expected) and
        Memory.compare(@dataof(text), @dataof(expected), @countof(expected)) == 0
}

#test
{
    var builder: StrConv.StringBuilder
    builder.appendString("abc")
    builder.zeroTerminate()

    @assert(builder.count() == 3)
    @assert(assertBuilderString(builder.toString(), "abc"))

    builder.zeroTerminate()
    @assert(builder.count() == 3)

    builder.appendString("def")
    @assert(builder.count() == 6)
    @assert(assertBuilderString(builder.moveToString(), "abcdef"))
}
