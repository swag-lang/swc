#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let value = Time.DateTime{2024, 2, 29, 13, 5, 9, 0}

    let en = Globalization.CultureInfo.fromName("en-US")
    Swag.assert(en.dateTimeFormat.formatDate(value) == "02/29/2024")
    Swag.assert(en.dateTimeFormat.formatDate(value, long: true) == "Thursday, February 29, 2024")
    Swag.assert(en.dateTimeFormat.formatTime(value) == "1:05:09 PM")
    Swag.assert(en.dateTimeFormat.formatTime(value, withSeconds: false) == "1:05 PM")

    let fr = Globalization.CultureInfo.fromName("fr-FR")
    Swag.assert(fr.dateTimeFormat.formatDate(value) == "29/02/2024")
    Swag.assert(fr.dateTimeFormat.formatDate(value, long: true) == "jeudi 29 f\u00E9vrier 2024")
    Swag.assert(fr.dateTimeFormat.formatTime(value) == "13:05:09")
    Swag.assert(fr.dateTimeFormat.formatDateTime(value) == "29/02/2024 13:05:09")

    let de = Globalization.CultureInfo.fromName("de-DE")
    Swag.assert(de.dateTimeFormat.formatDate(value) == "29.02.2024")
    Swag.assert(de.dateTimeFormat.formatDate(value, long: true) == "Donnerstag, 29. Februar 2024")

    let ja = Globalization.CultureInfo.fromName("ja-JP")
    Swag.assert(ja.dateTimeFormat.formatDate(value) == "2024/02/29")
}
