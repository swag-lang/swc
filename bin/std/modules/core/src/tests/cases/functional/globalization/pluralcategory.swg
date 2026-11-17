#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let en = Globalization.CultureInfo.fromName("en-US")
    Swag.require(en.ordinalPlural(0) == .Other)
    Swag.require(en.ordinalPlural(4) == .Other)
    Swag.require(en.ordinalPlural(11) == .Other)
    Swag.require(en.ordinalPlural(12) == .Other)
    Swag.require(en.ordinalPlural(13) == .Other)
    Swag.require(en.ordinalPlural(21) == .One)
    Swag.require(en.ordinalPlural(22) == .Two)
    Swag.require(en.ordinalPlural(23) == .Few)
    Swag.require(en.ordinalPlural(111) == .Other)

    let fr = Globalization.CultureInfo.fromName("fr-FR")
    Swag.require(fr.ordinalPlural(1) == .One)
    Swag.require(fr.ordinalPlural(2) == .Other)
}

#test
{
    let ar = Globalization.CultureInfo.fromName("ar-EG")
    Swag.require(ar.cardinalPlural(1) == .One)
    Swag.require(ar.cardinalPlural(3) == .Few)
    Swag.require(ar.cardinalPlural(10) == .Few)
    Swag.require(ar.cardinalPlural(11) == .Many)
    Swag.require(ar.cardinalPlural(99) == .Many)
    Swag.require(ar.cardinalPlural(100) == .Other)
    Swag.require(ar.cardinalPlural(1.5) == .Other)

    let ru = Globalization.CultureInfo.fromName("ru-RU")
    Swag.require(ru.cardinalPlural(0) == .Many)
    Swag.require(ru.cardinalPlural(4) == .Few)
    Swag.require(ru.cardinalPlural(14) == .Many)
    Swag.require(ru.cardinalPlural(20) == .Many)
    Swag.require(ru.cardinalPlural(1.5) == .Other)

    let pl = Globalization.CultureInfo.fromName("pl-PL")
    Swag.require(pl.cardinalPlural(0) == .Many)
    Swag.require(pl.cardinalPlural(12) == .Many)
}

#test
{
    let cs = Globalization.CultureInfo.fromName("cs-CZ")
    Swag.require(cs.cardinalPlural(0) == .Other)
    Swag.require(cs.cardinalPlural(2) == .Few)
    Swag.require(cs.cardinalPlural(4) == .Few)
    Swag.require(cs.cardinalPlural(5) == .Other)
    Swag.require(cs.cardinalPlural(1.5) == .Many)

    let ja = Globalization.CultureInfo.fromName("ja-JP")
    let zh = Globalization.CultureInfo.fromName("zh-CN")
    let ko = Globalization.CultureInfo.fromName("ko-KR")
    let th = Globalization.CultureInfo.fromName("th-TH")
    let vi = Globalization.CultureInfo.fromName("vi-VN")
    Swag.require(ja.cardinalPlural(1) == .Other)
    Swag.require(zh.cardinalPlural(1) == .Other)
    Swag.require(ko.cardinalPlural(1) == .Other)
    Swag.require(th.cardinalPlural(1) == .Other)
    Swag.require(vi.cardinalPlural(1) == .Other)
}
