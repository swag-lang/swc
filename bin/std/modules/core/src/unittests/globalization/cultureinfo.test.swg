#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let culture0 = Globalization.currentCulture()
    let culture1 = Globalization.currentCulture()
    @assert(culture0 == culture1)

    let oldNegativeSign     = culture0.numberFormat.negativeSign
    let oldPositiveSign     = culture0.numberFormat.positiveSign
    let oldDecimalSeparator = culture0.numberFormat.decimalSeparator

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

#test
{
    let en = Globalization.CultureInfo.fromName("en-US")
    let fr = Globalization.CultureInfo.fromName("fr-FR")
    let de = Globalization.CultureInfo.fromName("de-DE")
    let tr = Globalization.CultureInfo.fromName("tr-TR")

    @assert(en.name == "en-US")
    @assert(fr.numberFormat.decimalSeparator == ',')
    @assert(de.dateTimeFormat.monthName(3) == "M\u00E4rz")
    @assert(tr.toUpper("istanbul") == "\u0130STANBUL")
    @assert(tr.toLower("I\u0130") == "\u0131i")
    @assert(de.caseFold("Stra\u00DFe") == "strasse")

    let gb = Globalization.CultureInfo.fromName("en-GB")
    @assert(gb.currencyFormat.symbol == "\u00A3")
    @assert(gb.dateTimeFormat.dateOrder == .DayMonthYear)
}

#test
{
    let en = Globalization.CultureInfo.fromName("en-US")
    @assert(en.ordinalPlural(1) == .One)
    @assert(en.ordinalPlural(2) == .Two)
    @assert(en.ordinalPlural(3) == .Few)
    @assert(en.ordinalPlural(11) == .Other)
    @assert(en.cardinalPlural(1) == .One)
    @assert(en.cardinalPlural(2) == .Other)

    let fr = Globalization.CultureInfo.fromName("fr-FR")
    @assert(fr.cardinalPlural(0) == .One)
    @assert(fr.cardinalPlural(1.5) == .One)

    let ru = Globalization.CultureInfo.fromName("ru-RU")
    @assert(ru.cardinalPlural(1) == .One)
    @assert(ru.cardinalPlural(2) == .Few)
    @assert(ru.cardinalPlural(5) == .Many)
    @assert(ru.cardinalPlural(11) == .Many)
    @assert(ru.cardinalPlural(21) == .One)

    let ar = Globalization.CultureInfo.fromName("ar-EG")
    @assert(ar.cardinalPlural(0) == .Zero)
    @assert(ar.cardinalPlural(2) == .Two)
    @assert(ar.cardinalPlural(7) == .Few)
    @assert(ar.cardinalPlural(15) == .Many)

    let ja = Globalization.CultureInfo.fromName("ja-JP")
    @assert(ja.cardinalPlural(1) == .Other)

    let cs = Globalization.CultureInfo.fromName("cs-CZ")
    @assert(cs.cardinalPlural(3) == .Few)
    @assert(cs.cardinalPlural(1.5) == .Many)
}

#test
{
    let de = Globalization.CultureInfo.fromName("de-DE")
    @assert(de.sortKey("\u00C4pfel", ignoreCase: true) == "aepfel")
    @assert(de.compare("\u00C4pfel", "Azalee", ignoreCase: true) < 0)

    let sv = Globalization.CultureInfo.fromName("sv-SE")
    @assert(sv.compare("zebra", "\u00E5l", ignoreCase: true) < 0)
    @assert(sv.compare("\u00E5l", "\u00E4lg", ignoreCase: true) < 0)
    @assert(sv.compare("\u00E4lg", "\u00F6l", ignoreCase: true) < 0)
}
