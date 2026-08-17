#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var info: Globalization.NumberFormatInfo
    @assert(info.negativeSign == '-')
    @assert(info.positiveSign == '+')
    @assert(info.decimalSeparator == '.')
    @assert(info.groupSeparator == ',')
    @assert(info.groupSizes[0] == 3)
    @assert(info.groupSizeCount == 1)

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

#test
{
    let en = Globalization.CultureInfo.fromName("en-US")
    @assert(en.numberFormat.format(0'u64) == "0")
    @assert(en.numberFormat.format(1234567'u64, grouped: true) == "1,234,567")
    @assert(en.numberFormat.format(-9223372036854775807's64 - 1, grouped: true) == "-9,223,372,036,854,775,808")
    @assert(en.numberFormat.format(1234.5, 2, grouped: true) == "1,234.50")

    let fr = Globalization.CultureInfo.fromName("fr-FR")
    @assert(fr.numberFormat.format(1234567'u64, grouped: true) == "1\u202F234\u202F567")
    @assert(fr.numberFormat.format(1234.5, 2, grouped: true) == "1\u202F234,50")

    let hi = Globalization.CultureInfo.fromName("hi-IN")
    @assert(hi.numberFormat.format(1234567'u64, grouped: true) == "12,34,567")
}

#test
{
    let en = Globalization.CultureInfo.fromName("en-US")
    @assert(en.currencyFormat.format(1234.5, en.numberFormat) == "$1,234.50")
    @assert(en.currencyFormat.format(-1234.5, en.numberFormat) == "-$1,234.50")

    let fr = Globalization.CultureInfo.fromName("fr-FR")
    @assert(fr.currencyFormat.format(1234.5, fr.numberFormat) == "1\u202F234,50 \u20AC")
    @assert(fr.currencyFormat.format(-1234.5, fr.numberFormat) == "-1\u202F234,50 \u20AC")

    let ja = Globalization.CultureInfo.fromName("ja-JP")
    @assert(ja.currencyFormat.format(1200.0, ja.numberFormat) == "\u00A51,200")
}
