#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let culture0 = Globalization.currentCulture()
    let culture1 = Globalization.currentCulture()
    Swag.assert(culture0 == culture1)

    let oldNegativeSign     = culture0.numberFormat.negativeSign
    let oldPositiveSign     = culture0.numberFormat.positiveSign
    let oldDecimalSeparator = culture0.numberFormat.decimalSeparator

    culture0.numberFormat.negativeSign     = '~'
    culture0.numberFormat.positiveSign     = '^'
    culture0.numberFormat.decimalSeparator = ','

    Swag.assert(culture1.numberFormat.negativeSign == '~')
    Swag.assert(culture1.numberFormat.positiveSign == '^')
    Swag.assert(culture1.numberFormat.decimalSeparator == ',')

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

    Swag.assert(en.name == "en-US")
    Swag.assert(fr.numberFormat.decimalSeparator == ',')
    Swag.assert(de.dateTimeFormat.monthName(3) == "M\u00E4rz")
    Swag.assert(tr.toUpper("istanbul") == "\u0130STANBUL")
    Swag.assert(tr.toLower("I\u0130") == "\u0131i")
    Swag.assert(de.caseFold("Stra\u00DFe") == "strasse")

    let gb = Globalization.CultureInfo.fromName("en-GB")
    Swag.assert(gb.currencyFormat.symbol == "\u00A3")
    Swag.assert(gb.dateTimeFormat.dateOrder == .DayMonthYear)
}

#test
{
    let en = Globalization.CultureInfo.fromName("en-US")
    Swag.assert(en.ordinalPlural(1) == .One)
    Swag.assert(en.ordinalPlural(2) == .Two)
    Swag.assert(en.ordinalPlural(3) == .Few)
    Swag.assert(en.ordinalPlural(11) == .Other)
    Swag.assert(en.cardinalPlural(1) == .One)
    Swag.assert(en.cardinalPlural(2) == .Other)

    let fr = Globalization.CultureInfo.fromName("fr-FR")
    Swag.assert(fr.cardinalPlural(0) == .One)
    Swag.assert(fr.cardinalPlural(1.5) == .One)

    let ru = Globalization.CultureInfo.fromName("ru-RU")
    Swag.assert(ru.cardinalPlural(1) == .One)
    Swag.assert(ru.cardinalPlural(2) == .Few)
    Swag.assert(ru.cardinalPlural(5) == .Many)
    Swag.assert(ru.cardinalPlural(11) == .Many)
    Swag.assert(ru.cardinalPlural(21) == .One)

    let ar = Globalization.CultureInfo.fromName("ar-EG")
    Swag.assert(ar.cardinalPlural(0) == .Zero)
    Swag.assert(ar.cardinalPlural(2) == .Two)
    Swag.assert(ar.cardinalPlural(7) == .Few)
    Swag.assert(ar.cardinalPlural(15) == .Many)

    let ja = Globalization.CultureInfo.fromName("ja-JP")
    Swag.assert(ja.cardinalPlural(1) == .Other)

    let cs = Globalization.CultureInfo.fromName("cs-CZ")
    Swag.assert(cs.cardinalPlural(3) == .Few)
    Swag.assert(cs.cardinalPlural(1.5) == .Many)
}

#test
{
    let de = Globalization.CultureInfo.fromName("de-DE")
    Swag.assert(de.sortKey("\u00C4pfel", ignoreCase: true) == "aepfel")
    Swag.assert(de.compare("\u00C4pfel", "Azalee", ignoreCase: true) < 0)

    let sv = Globalization.CultureInfo.fromName("sv-SE")
    Swag.assert(sv.compare("zebra", "\u00E5l", ignoreCase: true) < 0)
    Swag.assert(sv.compare("\u00E5l", "\u00E4lg", ignoreCase: true) < 0)
    Swag.assert(sv.compare("\u00E4lg", "\u00F6l", ignoreCase: true) < 0)
}
