#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let culture0 = Globalization.currentCulture()
    let culture1 = Globalization.currentCulture()
    Swag.require(culture0 == culture1)

    let oldNegativeSign     = culture0.numberFormat.negativeSign
    let oldPositiveSign     = culture0.numberFormat.positiveSign
    let oldDecimalSeparator = culture0.numberFormat.decimalSeparator

    culture0.numberFormat.negativeSign     = '~'
    culture0.numberFormat.positiveSign     = '^'
    culture0.numberFormat.decimalSeparator = ','

    Swag.require(culture1.numberFormat.negativeSign == '~')
    Swag.require(culture1.numberFormat.positiveSign == '^')
    Swag.require(culture1.numberFormat.decimalSeparator == ',')

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

    Swag.require(en.name == "en-US")
    Swag.require(fr.numberFormat.decimalSeparator == ',')
    Swag.require(de.dateTimeFormat.monthName(3) == "M\u00E4rz")
    Swag.require(tr.toUpper("istanbul") == "\u0130STANBUL")
    Swag.require(tr.toLower("I\u0130") == "\u0131i")
    Swag.require(de.caseFold("Stra\u00DFe") == "strasse")

    let gb = Globalization.CultureInfo.fromName("en-GB")
    Swag.require(gb.currencyFormat.symbol == "\u00A3")
    Swag.require(gb.dateTimeFormat.dateOrder == .DayMonthYear)
}

#test
{
    let en = Globalization.CultureInfo.fromName("en-US")
    Swag.require(en.ordinalPlural(1) == .One)
    Swag.require(en.ordinalPlural(2) == .Two)
    Swag.require(en.ordinalPlural(3) == .Few)
    Swag.require(en.ordinalPlural(11) == .Other)
    Swag.require(en.cardinalPlural(1) == .One)
    Swag.require(en.cardinalPlural(2) == .Other)

    let fr = Globalization.CultureInfo.fromName("fr-FR")
    Swag.require(fr.cardinalPlural(0) == .One)
    Swag.require(fr.cardinalPlural(1.5) == .One)

    let ru = Globalization.CultureInfo.fromName("ru-RU")
    Swag.require(ru.cardinalPlural(1) == .One)
    Swag.require(ru.cardinalPlural(2) == .Few)
    Swag.require(ru.cardinalPlural(5) == .Many)
    Swag.require(ru.cardinalPlural(11) == .Many)
    Swag.require(ru.cardinalPlural(21) == .One)

    let ar = Globalization.CultureInfo.fromName("ar-EG")
    Swag.require(ar.cardinalPlural(0) == .Zero)
    Swag.require(ar.cardinalPlural(2) == .Two)
    Swag.require(ar.cardinalPlural(7) == .Few)
    Swag.require(ar.cardinalPlural(15) == .Many)

    let ja = Globalization.CultureInfo.fromName("ja-JP")
    Swag.require(ja.cardinalPlural(1) == .Other)

    let cs = Globalization.CultureInfo.fromName("cs-CZ")
    Swag.require(cs.cardinalPlural(3) == .Few)
    Swag.require(cs.cardinalPlural(1.5) == .Many)
}

#test
{
    let de = Globalization.CultureInfo.fromName("de-DE")
    Swag.require(de.sortKey("\u00C4pfel", ignoreCase: true) == "aepfel")
    Swag.require(de.compare("\u00C4pfel", "Azalee", ignoreCase: true) < 0)

    let sv = Globalization.CultureInfo.fromName("sv-SE")
    Swag.require(sv.compare("zebra", "\u00E5l", ignoreCase: true) < 0)
    Swag.require(sv.compare("\u00E5l", "\u00E4lg", ignoreCase: true) < 0)
    Swag.require(sv.compare("\u00E4lg", "\u00F6l", ignoreCase: true) < 0)
}
