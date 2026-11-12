#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let format: Globalization.DateTimeFormatInfo
    Swag.require(not format.matches("pattern", Swag.U64.Max, "x"))
}

#test
{
    let value = Time.DateTime{2024, 2, 29, 13, 5, 9, 0}

    let en = Globalization.CultureInfo.fromName("en-US")
    Swag.require(en.dateTimeFormat.formatDate(value) == "02/29/2024")
    Swag.require(en.dateTimeFormat.formatDate(value, long: true) == "Thursday, February 29, 2024")
    Swag.require(en.dateTimeFormat.formatTime(value) == "1:05:09 PM")
    Swag.require(en.dateTimeFormat.formatTime(value, withSeconds: false) == "1:05 PM")

    let fr = Globalization.CultureInfo.fromName("fr-FR")
    Swag.require(fr.dateTimeFormat.formatDate(value) == "29/02/2024")
    Swag.require(fr.dateTimeFormat.formatDate(value, long: true) == "jeudi 29 f\u00E9vrier 2024")
    Swag.require(fr.dateTimeFormat.formatTime(value) == "13:05:09")
    Swag.require(fr.dateTimeFormat.formatDateTime(value) == "29/02/2024 13:05:09")

    let de = Globalization.CultureInfo.fromName("de-DE")
    Swag.require(de.dateTimeFormat.formatDate(value) == "29.02.2024")
    Swag.require(de.dateTimeFormat.formatDate(value, long: true) == "Donnerstag, 29. Februar 2024")

    let ja = Globalization.CultureInfo.fromName("ja-JP")
    Swag.require(ja.dateTimeFormat.formatDate(value) == "2024/02/29")
}

#test
{
    let midnight = Time.DateTime{2024, 2, 29, 0, 0, 0, 0}
    let noon     = Time.DateTime{2024, 2, 29, 12, 0, 0, 0}
    let en       = Globalization.CultureInfo.fromName("en-US")
    let fr       = Globalization.CultureInfo.fromName("fr-FR")

    Swag.require(en.dateTimeFormat.formatTime(midnight) == "12:00:00 AM")
    Swag.require(en.dateTimeFormat.formatTime(noon) == "12:00:00 PM")
    Swag.require(fr.dateTimeFormat.formatTime(midnight) == "00:00:00")
    Swag.require(fr.dateTimeFormat.formatTime(noon) == "12:00:00")
}
