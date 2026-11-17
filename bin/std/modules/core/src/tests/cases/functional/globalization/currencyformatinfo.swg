#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var currency: Globalization.CurrencyFormatInfo
    currency.symbol = "¤"

    var number: Globalization.NumberFormatInfo

    currency.positivePattern = .SymbolBefore
    Swag.require(currency.format(1234.5, number) == "¤1,234.50")
    currency.positivePattern = .SymbolBeforeWithSpace
    Swag.require(currency.format(1234.5, number) == "¤ 1,234.50")
    currency.positivePattern = .SymbolAfter
    Swag.require(currency.format(1234.5, number) == "1,234.50¤")
    currency.positivePattern = .SymbolAfterWithSpace
    Swag.require(currency.format(1234.5, number) == "1,234.50 ¤")
}

#test
{
    var currency: Globalization.CurrencyFormatInfo
    currency.symbol = "¤"
    var number: Globalization.NumberFormatInfo
    number.negativeSign = '~'

    currency.negativePattern = .SignBeforeSymbol
    currency.positivePattern = .SymbolBefore
    Swag.require(currency.format(-1234.5, number) == "~¤1,234.50")
    currency.positivePattern = .SymbolBeforeWithSpace
    Swag.require(currency.format(-1234.5, number) == "~¤ 1,234.50")
    currency.positivePattern = .SymbolAfter
    Swag.require(currency.format(-1234.5, number) == "~1,234.50¤")
    currency.positivePattern = .SymbolAfterWithSpace
    Swag.require(currency.format(-1234.5, number) == "~1,234.50 ¤")

    currency.negativePattern = .SignBeforeNumber
    currency.positivePattern = .SymbolBefore
    Swag.require(currency.format(-1234.5, number) == "¤~1,234.50")
    currency.positivePattern = .SymbolBeforeWithSpace
    Swag.require(currency.format(-1234.5, number) == "¤ ~1,234.50")
    currency.positivePattern = .SymbolAfter
    Swag.require(currency.format(-1234.5, number) == "~1,234.50¤")
    currency.positivePattern = .SymbolAfterWithSpace
    Swag.require(currency.format(-1234.5, number) == "~1,234.50 ¤")

    currency.negativePattern = .Parentheses
    currency.positivePattern = .SymbolAfterWithSpace
    Swag.require(currency.format(-1234.5, number) == "(1,234.50 ¤)")
}

#test
{
    var currency: Globalization.CurrencyFormatInfo
    currency.symbol = "€"
    currency.decimalDigits = 3
    var number: Globalization.NumberFormatInfo

    Swag.require(currency.format(12.5, number) == "€12.500")

    currency.decimalDigits = 2
    Swag.require(currency.format(-0.001, number) == "€0.00")
}
