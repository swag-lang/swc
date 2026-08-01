#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var info: Globalization.NumberFormatInfo
    @assert(info.negativeSign == '-')
    @assert(info.positiveSign == '+')
    @assert(info.decimalSeparator == '.')

    info.negativeSign     = '~'
    info.positiveSign     = '^'
    info.decimalSeparator = ','

    @assert(info.negativeSign == '~')
    @assert(info.positiveSign == '^')
    @assert(info.decimalSeparator == ',')

    let culture = Globalization.currentCulture()
    @assert(culture.numberFormat.negativeSign == '-')
    @assert(culture.numberFormat.positiveSign == '+')
    @assert(culture.numberFormat.decimalSeparator == '.')
}
