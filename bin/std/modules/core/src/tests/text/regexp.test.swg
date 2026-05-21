#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var literal: Parser.RegExp
    discard catch literal.preprocess("1")

    @assert(literal.preprocessed.contains('1'))
}

#test
{
    var digitClass: Parser.RegExp
    discard catch digitClass.preprocess("\\d")

    @assert(digitClass.preprocessed.contains(Parser.RuneAsciiDigit))
}
