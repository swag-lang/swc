#global namespace Globalization

using Swag

// Groups the conventions used to format, compare, and inflect text for one locale.
//
// Values returned by [[CultureInfo.fromName]] own their locale name and can be copied
// freely. An unrecognized locale receives invariant English conventions while retaining
// its requested name.
public struct CultureInfo
{
    public
    {
        name:           String                 // Owned BCP 47 locale name represented by this value.
        numberFormat:   NumberFormatInfo       // Numeric formatting conventions.
        currencyFormat: CurrencyFormatInfo     // Currency formatting conventions.
        dateTimeFormat: DateTimeFormatInfo     // Date and time names and patterns.
    }
}

public impl CultureInfo
{
    internal mtd const isLanguage(language: string)->bool
    {
        let name = .name.toString()
        if name.count < language.count do
            return false
        if Utf8.compare(Swag.makeSlice(name.buffer, language.count), Swag.makeSlice(language.buffer, language.count), .Latin1NoCase) != 0 do
            return false
        return name.count == language.count or name[language.count] == '-'
    }

    internal mtd const isNamed(locale: string)->bool
    {
        return Utf8.compare(.name.toSlice(), Swag.makeSlice(locale.buffer, locale.count), .Latin1NoCase) == 0
    }

    internal func englishDateTime()->DateTimeFormatInfo
    {
        var result: retval
        return result
    }

    // Creates formatting and language rules for a BCP 47 locale name.
    //
    // The built-in profiles cover English, French, German, Hindi, Turkish,
    // Russian, Arabic, Japanese, Swedish, Polish, and Czech. Other locale names
    // use invariant English display data and the general plural rules.
    func fromName(name: string)->CultureInfo
    {
        var result: retval
        result.name                  = name
        result.dateTimeFormat        = CultureInfo.englishDateTime()
        result.currencyFormat.symbol = "$"

        if result.isNamed("en-GB")
        {
            result.currencyFormat.symbol           = "\u00A3"
            result.currencyFormat.negativePattern  = .SignBeforeSymbol
            result.dateTimeFormat.shortDatePattern = "dd/MM/yyyy"
            result.dateTimeFormat.longDatePattern  = "dddd, d MMMM yyyy"
            result.dateTimeFormat.shortTimePattern = "HH:mm"
            result.dateTimeFormat.longTimePattern  = "HH:mm:ss"
            result.dateTimeFormat.dateOrder        = .DayMonthYear
            result.dateTimeFormat.uses24Hour       = true
        }
        elif result.isNamed("en-AU") or result.isNamed("en-NZ")
        {
            result.dateTimeFormat.shortDatePattern = "dd/MM/yyyy"
            result.dateTimeFormat.longDatePattern  = "dddd, d MMMM yyyy"
            result.dateTimeFormat.shortTimePattern = "HH:mm"
            result.dateTimeFormat.longTimePattern  = "HH:mm:ss"
            result.dateTimeFormat.dateOrder        = .DayMonthYear
            result.dateTimeFormat.uses24Hour       = true
        }
        elif result.isLanguage("fr")
        {
            result.numberFormat.decimalSeparator   = ','
            result.numberFormat.groupSeparator     = 0x202F
            result.currencyFormat.symbol           = "\u20AC"
            result.currencyFormat.positivePattern  = .SymbolAfterWithSpace
            result.currencyFormat.negativePattern  = .SignBeforeNumber
            result.dateTimeFormat.monthNames       = ["janvier", "f\u00E9vrier", "mars", "avril", "mai", "juin", "juillet", "ao\u00FBt", "septembre", "octobre", "novembre", "d\u00E9cembre"]
            result.dateTimeFormat.dayNames         = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
            result.dateTimeFormat.shortDatePattern = "dd/MM/yyyy"
            result.dateTimeFormat.longDatePattern  = "dddd d MMMM yyyy"
            result.dateTimeFormat.shortTimePattern = "HH:mm"
            result.dateTimeFormat.longTimePattern  = "HH:mm:ss"
            result.dateTimeFormat.dateOrder        = .DayMonthYear
            result.dateTimeFormat.uses24Hour       = true
        }
        elif result.isLanguage("de")
        {
            result.numberFormat.decimalSeparator   = ','
            result.numberFormat.groupSeparator     = '.'
            result.currencyFormat.symbol           = "\u20AC"
            result.currencyFormat.positivePattern  = .SymbolAfterWithSpace
            result.currencyFormat.negativePattern  = .SignBeforeNumber
            result.dateTimeFormat.monthNames       = ["Januar", "Februar", "M\u00E4rz", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
            result.dateTimeFormat.dayNames         = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
            result.dateTimeFormat.shortDatePattern = "dd/MM/yyyy"
            result.dateTimeFormat.longDatePattern  = "dddd, d. MMMM yyyy"
            result.dateTimeFormat.shortTimePattern = "HH:mm"
            result.dateTimeFormat.longTimePattern  = "HH:mm:ss"
            result.dateTimeFormat.dateSeparator    = '.'
            result.dateTimeFormat.dateOrder        = .DayMonthYear
            result.dateTimeFormat.uses24Hour       = true
        }
        elif result.isLanguage("hi")
        {
            result.numberFormat.groupSizes         = [3, 2]
            result.numberFormat.groupSizeCount     = 2
            result.currencyFormat.symbol           = "\u20B9"
            result.dateTimeFormat.shortDatePattern = "dd/MM/yyyy"
            result.dateTimeFormat.dateOrder        = .DayMonthYear
        }
        elif result.isLanguage("tr")
        {
            result.numberFormat.decimalSeparator   = ','
            result.numberFormat.groupSeparator     = '.'
            result.currencyFormat.symbol           = "\u20BA"
            result.currencyFormat.positivePattern  = .SymbolAfterWithSpace
            result.dateTimeFormat.monthNames       = ["Ocak", "\u015Eubat", "Mart", "Nisan", "May\u0131s", "Haziran", "Temmuz", "A\u011Fustos", "Eyl\u00FCl", "Ekim", "Kas\u0131m", "Aral\u0131k"]
            result.dateTimeFormat.dayNames         = ["Pazar", "Pazartesi", "Sal\u0131", "\u00C7ar\u015Famba", "Per\u015Fembe", "Cuma", "Cumartesi"]
            result.dateTimeFormat.shortDatePattern = "dd/MM/yyyy"
            result.dateTimeFormat.longDatePattern  = "d MMMM yyyy dddd"
            result.dateTimeFormat.shortTimePattern = "HH:mm"
            result.dateTimeFormat.longTimePattern  = "HH:mm:ss"
            result.dateTimeFormat.dateSeparator    = '.'
            result.dateTimeFormat.dateOrder        = .DayMonthYear
            result.dateTimeFormat.uses24Hour       = true
        }
        elif result.isLanguage("ru") or result.isLanguage("pl") or result.isLanguage("cs")
        {
            result.numberFormat.decimalSeparator   = ','
            result.numberFormat.groupSeparator     = 0x00A0
            result.dateTimeFormat.shortDatePattern = "dd/MM/yyyy"
            result.dateTimeFormat.shortTimePattern = "HH:mm"
            result.dateTimeFormat.longTimePattern  = "HH:mm:ss"
            result.dateTimeFormat.dateSeparator    = '.'
            result.dateTimeFormat.dateOrder        = .DayMonthYear
            result.dateTimeFormat.uses24Hour       = true
        }
        elif result.isLanguage("ja")
        {
            result.currencyFormat.symbol           = "\u00A5"
            result.currencyFormat.decimalDigits    = 0
            result.dateTimeFormat.shortDatePattern = "yyyy/MM/dd"
            result.dateTimeFormat.longDatePattern  = "yyyy\u5E74M\u6708d\u65E5dddd"
            result.dateTimeFormat.shortTimePattern = "H:mm"
            result.dateTimeFormat.longTimePattern  = "H:mm:ss"
            result.dateTimeFormat.dateOrder        = .YearMonthDay
            result.dateTimeFormat.uses24Hour       = true
        }
        elif result.isLanguage("ar")
        {
            result.currencyFormat.symbol           = "\u062C.\u0645."
            result.currencyFormat.positivePattern  = .SymbolAfterWithSpace
            result.dateTimeFormat.shortDatePattern = "dd/MM/yyyy"
            result.dateTimeFormat.shortTimePattern = "HH:mm"
            result.dateTimeFormat.longTimePattern  = "HH:mm:ss"
            result.dateTimeFormat.dateOrder        = .DayMonthYear
            result.dateTimeFormat.uses24Hour       = true
        }

        return result
    }

    // Returns the cardinal plural category for a number in this locale.
    mtd const cardinalPlural(value: f64)->PluralCategory
    {
        let absolute = Math.abs(value)
        let integer  = cast(u64) Math.trunc(absolute)
        let integral = absolute == cast(f64) integer

        if .isLanguage("ja") or .isLanguage("zh") or .isLanguage("ko") or .isLanguage("th") or .isLanguage("vi") do
            return .Other

        if .isLanguage("ar") and integral
        {
            if integer == 0 do
                return .Zero
            if integer == 1 do
                return .One
            if integer == 2 do
                return .Two
            let mod100 = integer % 100
            if mod100 >= 3 and mod100 <= 10 do
                return .Few
            if mod100 >= 11 and mod100 <= 99 do
                return .Many
            return .Other
        }

        if .isLanguage("ru") and integral
        {
            let mod10  = integer % 10
            let mod100 = integer % 100
            if mod10 == 1 and mod100 != 11 do
                return .One
            if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14) do
                return .Few
            if mod10 == 0 or mod10 >= 5 or (mod100 >= 11 and mod100 <= 14) do
                return .Many
            return .Other
        }

        if .isLanguage("pl") and integral
        {
            if integer == 1 do
                return .One
            let mod10  = integer % 10
            let mod100 = integer % 100
            if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14) do
                return .Few
            return .Many
        }

        if .isLanguage("cs") or .isLanguage("sk")
        {
            if !integral do
                return .Many
            if integer == 1 do
                return .One
            if integer >= 2 and integer <= 4 do
                return .Few
            return .Other
        }

        if .isLanguage("fr") and integer <= 1 do
            return .One
        if .isLanguage("hi") and (integer == 0 or absolute == 1) do
            return .One
        return integral and integer == 1 ? .One : .Other
    }

    // Returns the ordinal plural category for a non-negative integer in this locale.
    mtd const ordinalPlural(value: u64)->PluralCategory
    {
        if .isLanguage("en")
        {
            let mod10  = value % 10
            let mod100 = value % 100
            if mod10 == 1 and mod100 != 11 do
                return .One
            if mod10 == 2 and mod100 != 12 do
                return .Two
            if mod10 == 3 and mod100 != 13 do
                return .Few
        }
        elif .isLanguage("fr") and value == 1 do
            return .One
        return .Other
    }

    // Converts text to upper case with this locale's special casing rules.
    mtd const toUpper(value: string)->String
    {
        var result: retval
        let turkic = .isLanguage("tr") or .isLanguage("az")
        Utf8.visitRunes(Swag.makeSlice(value.buffer, value.count))
        {
            if turkic and c == 'i' do
                result.append(0x0130)
            elif turkic and c == 0x0131 do
                result.append(cast(rune) 'I')
            elif c == 0x00DF do
                result.append("SS")
            else do
                result.append(Unicode.toUpper(c))
        }

        return result
    }

    // Converts text to lower case with this locale's special casing rules.
    mtd const toLower(value: string)->String
    {
        var result: retval
        let turkic = .isLanguage("tr") or .isLanguage("az")
        Utf8.visitRunes(Swag.makeSlice(value.buffer, value.count))
        {
            if turkic and c == 'I' do
                result.append(0x0131)
            elif turkic and c == 0x0130 do
                result.append(cast(rune) 'i')
            else do
                result.append(Unicode.toLower(c))
        }

        return result
    }

    // Produces a locale-sensitive case-folded value for caseless matching.
    mtd const caseFold(value: string)->String
    {
        var result: retval
        let turkic = .isLanguage("tr") or .isLanguage("az")
        Utf8.visitRunes(Swag.makeSlice(value.buffer, value.count))
        {
            if c == 0x00DF do
                result.append("ss")
            elif c == 0x03C2 do
                result.append(0x03C3)
            elif turkic and c == 'I' do
                result.append(0x0131)
            elif turkic and c == 0x0130 do
                result.append(cast(rune) 'i')
            else do
                result.append(Unicode.toLower(c))
        }

        return result
    }

    // Produces a stable primary sort key using this locale's collation tailoring.
    //
    // Compare keys as ordinal UTF-8 bytes. A key owns its storage and remains valid
    // independently of the source string.
    mtd const sortKey(value: string, ignoreCase = false)->String
    {
        let source      = ignoreCase ? .caseFold(value) : String.from(value)
        var result: retval
        let sourceSlice = source.toSlice()
        Utf8.visitRunes(sourceSlice)
        {
            var handled = false
            if .isLanguage("de")
            {
                switch c
                {
                case 0x00E4, 0x00C4:
                    result.append("ae")
                    handled = true

                case 0x00F6, 0x00D6:
                    result.append("oe")
                    handled = true

                case 0x00FC, 0x00DC:
                    result.append("ue")
                    handled = true

                case 0x00DF:
                    result.append("ss")
                    handled = true
                }
            }

            if !handled and .isLanguage("sv")
            {
                switch c
                {
                case 0x00E5, 0x00C5:
                    result.append("{a")
                    handled = true

                case 0x00E4, 0x00C4:
                    result.append("{b")
                    handled = true

                case 0x00F6, 0x00D6:
                    result.append("{c")
                    handled = true
                }
            }

            if !handled
            {
                switch c
                {
                case 0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, 0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5: result.append('a'u8)
                case 0x00E7, 0x00C7:                                                                                 result.append('c'u8)
                case 0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00C8, 0x00C9, 0x00CA, 0x00CB:                                 result.append('e'u8)
                case 0x00EC, 0x00ED, 0x00EE, 0x00EF, 0x00CC, 0x00CD, 0x00CE, 0x00CF:                                 result.append('i'u8)
                case 0x00F1, 0x00D1:                                                                                 result.append('n'u8)
                case 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6:                 result.append('o'u8)
                case 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x00D9, 0x00DA, 0x00DB, 0x00DC:                                 result.append('u'u8)
                default:                                                                                             result.append(c)
                }
            }
        }

        return result
    }

    // Compares two strings according to this locale's primary collation order.
    //
    // Diacritics are primary-equivalent in most profiles and are used as a stable
    // tie-breaker. German phonebook and Swedish alphabetic tailoring are applied.
    mtd const compare(left, right: string, ignoreCase = false)->s32
    {
        let leftKey  = .sortKey(left, ignoreCase)
        let rightKey = .sortKey(right, ignoreCase)
        let primary  = Utf8.compare(leftKey.toSlice(), rightKey.toSlice(), .Unicode)
        if primary do
            return primary
        return Utf8.compare(Swag.makeSlice(left.buffer, left.count), Swag.makeSlice(right.buffer, right.count), ignoreCase ? .UnicodeNoCase : .Unicode)
    }
}

var g_CultureInfo:            CultureInfo
var g_CultureInfoInitialized: bool

// Returns the mutable process-wide culture settings.
public func currentCulture()->*CultureInfo
{
    if !g_CultureInfoInitialized
    {
        g_CultureInfo            = CultureInfo.fromName("en-US")
        g_CultureInfoInitialized = true
    }

    return &g_CultureInfo
}
