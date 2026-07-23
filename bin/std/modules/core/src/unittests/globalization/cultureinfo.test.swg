#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let culture0 = Globalization.getCultureInfo()
    let culture1 = Globalization.getCultureInfo()
    @assert(culture0 == culture1)

    let oldNegativeSign      = culture0.numberFormat.negativeSign
    let oldPositiveSign      = culture0.numberFormat.positiveSign
    let oldDecimalSeparator  = culture0.numberFormat.decimalSeparator

    culture0.numberFormat.negativeSign     = '~'
    culture0.numberFormat.positiveSign     = '^'
    culture0.numberFormat.decimalSeparator = ','

    @assert(culture1.numberFormat.negativeSign == '~')
    @assert(culture1.numberFormat.positiveSign == '^')
    @assert(culture1.numberFormat.decimalSeparator == ',')

    culture0.numberFormat.negativeSign     = oldNegativeSign
    culture0.numberFormat.positiveSign     = oldPositiveSign
    culture0.numberFormat.decimalSeparator = oldDecimalSeparator
}
