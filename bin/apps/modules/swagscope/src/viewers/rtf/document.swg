#global internal
#global namespace Viewers.Rtf

using Core

// The formatted, bounded body of one Rich Text Format document.
struct Document
{
    html:           String
    paragraphs:     u64
    omittedObjects: u64
}

private enum Alignment
{
    Left
    Center
    Right
    Justify
}

// Character formatting and destination visibility are scoped by RTF groups.
private struct State
{
    bold:      bool
    italic:    bool
    underline: bool
    strike:    bool
    hidden:    bool
    skip:      bool
    unicodeFallback: u32 = 1
}

private struct Reader
{
    bytes:       Array'u8
    offset:      u64
    groups:      Array'State
    state:       State
    shown:       State
    alignment:   Alignment
    paragraph:   String
    document:    Document
    sawHeader:   bool
    tableOpen:   bool
    rowHasCell:  bool
    highSurrogate: u32
}

impl Document
{
    // Parses RTF without executing fields, loading linked resources, or decoding embedded objects.
    func load(fileName: string)->Document fail
    {
        let info = try File.info(fileName)
        if info.size > 8 * 1024 * 1024 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}

        var reader: Reader
        reader.bytes = try File.readAllBytes(fileName)
        return try reader.read()
    }
}

private impl Reader
{
    mtd read()->Document fail
    {
        if .bytes.count < 6 or .bytes[0] != '{' or .bytes[1] != '\\' do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        .document.html = "<html><body>"

        while .offset < .bytes.count
        {
            let value = .bytes[.offset]
            if .groups.isEmpty() and .offset != 0
            {
                if value != ' ' and value != '\r' and value != '\n' do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                .offset += 1
                continue
            }

            switch value
            {
            case '{':
                if .groups.count >= 128 do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                .groups.add(.state)
                .offset += 1

            case '}':
                if .groups.isEmpty() do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                .state = .groups[.groups.count - 1]
                .groups.resize(.groups.count - 1)
                .offset += 1

            case '\\':
                try .control()

            case '\r', '\n':
                .offset += 1

            default:
                let start = .offset
                while .offset < .bytes.count and
                      .bytes[.offset] != '{' and .bytes[.offset] != '}' and .bytes[.offset] != '\\' and
                      .bytes[.offset] != '\r' and .bytes[.offset] != '\n' do
                    .offset += 1
                if not .state.skip and not .state.hidden do
                    .appendText(Text.decode(.bytes.toSlice()[start until .offset], .Windows1252))
            }

            if .document.html.count + .paragraph.count > 32 * 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        if not .sawHeader or not .groups.isEmpty() do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if .tableOpen do
            .finishRow()
        if not .paragraph.isEmpty() do
            .finishParagraph(force: false)
        if not .document.paragraphs do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        .document.html += "</body></html>"
        return #move .document
    }

    mtd control() fail
    {
        .offset += 1
        if .offset >= .bytes.count do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        let symbol = .bytes[.offset]
        if not Latin1.isLetter(symbol)
        {
            .offset += 1
            switch symbol
            {
            case '\\', '{', '}': .appendRune(cast(rune, symbol))
            case '~':           .appendRune(0xA0)
            case '-':           .appendRune(0xAD)
            case '_':           .appendRune(0x2011)
            case '*':           .state.skip = true
            case '\'':
                if .offset + 2 > .bytes.count do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                let first = .hexDigit(.bytes[.offset])
                let second = .hexDigit(.bytes[.offset + 1])
                if first < 0 or second < 0 do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                .offset += 2
                var encoded: [1] u8 = [cast(u8, first * 16 + second)]
                .appendText(Text.decode(encoded, .Windows1252))
            }
            return
        }

        let start = .offset
        while .offset < .bytes.count and Latin1.isLetter(.bytes[.offset]) do
            .offset += 1
        let word = cast(string, .bytes.toSlice()[start until .offset])
        var number: s32
        var hasNumber: bool
        var negative: bool
        if .offset < .bytes.count and .bytes[.offset] == '-'
        {
            negative = true
            .offset += 1
        }
        while .offset < .bytes.count and Latin1.isDigit(.bytes[.offset])
        {
            hasNumber = true
            if number > 100_000_000 do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            number = number * 10 + cast(s32, .bytes[.offset] - '0')
            .offset += 1
        }
        if negative and hasNumber do
            number = -number
        if .offset < .bytes.count and .bytes[.offset] == ' ' do
            .offset += 1

        if word == "bin"
        {
            if not hasNumber or number < 0 or cast(u64, number) > .bytes.count - .offset do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            .offset += cast(u64, number)
            return
        }
        if word == "rtf"
        {
            if start != 2 or .sawHeader do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            .sawHeader = hasNumber and number >= 1
            return
        }
        if word == "ansicpg"
        {
            if not hasNumber or number != 1252 do
                fail Errors.UnsupportedFormatError{texts().err_CodePage}
            return
        }
        if word == "uc"
        {
            if not hasNumber or number < 0 or number > 16 do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            .state.unicodeFallback = cast(u32, number)
            return
        }
        if word == "u"
        {
            if not hasNumber or number < -32768 or number > 32767 do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            .appendUnicodeUnit(cast(u32, number < 0 ? number + 65536 : number))
            .skipUnicodeFallback()
            return
        }
        if .state.skip do
            return

        switch word
        {
        case "fonttbl", "colortbl", "stylesheet", "info", "generator", "filetbl", "listtable",
             "listoverridetable", "xmlnstbl", "datastore", "themedata", "colorschememapping",
             "header", "headerl", "headerr", "footer", "footerl", "footerr", "footnote",
             "annotation", "fldinst":
            .state.skip = true

        case "pict", "object":
            .document.omittedObjects += 1
            .appendText(word == "pict" ? texts().ui_ImageOmitted : texts().ui_ObjectOmitted)
            .state.skip = true

        case "b":       .state.bold      = not hasNumber or number != 0
        case "i":       .state.italic    = not hasNumber or number != 0
        case "ul":      .state.underline = not hasNumber or number != 0
        case "ulnone":  .state.underline = false
        case "strike":  .state.strike    = not hasNumber or number != 0
        case "v":       .state.hidden    = not hasNumber or number != 0
        case "plain":
            .state.bold = false
            .state.italic = false
            .state.underline = false
            .state.strike = false
            .state.hidden = false

        case "ql":   .alignment = .Left
        case "qc":   .alignment = .Center
        case "qr":   .alignment = .Right
        case "qj":   .alignment = .Justify
        case "pard": .alignment = .Left

        case "par":
            if .tableOpen do
                .appendHtml("<br>")
            else do
                .finishParagraph(force: true)
        case "line": .appendHtml("<br>")
        case "tab":  .appendHtml("&emsp;")
        case "page":
            .finishParagraph(force: false)
            .document.html += "<hr>"
        case "trowd":
            if .tableOpen do
                .finishRow()
            .finishParagraph(force: false)
            .document.html += "<table><tr>"
            .tableOpen = true
            .rowHasCell = false
        case "cell":
            if .tableOpen do
                .finishCell()
        case "row":
            if .tableOpen do
                .finishRow()

        case "bullet":   .appendRune(0x2022)
        case "emdash":   .appendRune(0x2014)
        case "endash":   .appendRune(0x2013)
        case "lquote":   .appendRune(0x2018)
        case "rquote":   .appendRune(0x2019)
        case "ldblquote": .appendRune(0x201C)
        case "rdblquote": .appendRune(0x201D)
        }
    }

    mtd skipUnicodeFallback()
    {
        var remaining = .state.unicodeFallback
        while remaining and .offset < .bytes.count
        {
            if .bytes[.offset] == '\\' and .offset + 1 < .bytes.count
            {
                if .bytes[.offset + 1] == '\'' and .offset + 3 < .bytes.count do
                    .offset += 4
                else do
                    .offset += 2
            }
            elif .bytes[.offset] != '{' and .bytes[.offset] != '}' do
                .offset += 1
            else do
                break
            remaining -= 1
        }
    }

    mtd appendUnicodeUnit(unit: u32)
    {
        if .state.skip or .state.hidden
        {
            .highSurrogate = 0
            return
        }
        if unit >= 0xD800 and unit <= 0xDBFF
        {
            if .highSurrogate do
                .appendRune(0xFFFD)
            .highSurrogate = unit
            return
        }
        if unit >= 0xDC00 and unit <= 0xDFFF and .highSurrogate
        {
            .appendRune(cast(rune, 0x10000 + (.highSurrogate - 0xD800) * 0x400 + unit - 0xDC00))
            .highSurrogate = 0
            return
        }
        if .highSurrogate do
            .appendRune(0xFFFD)
        .highSurrogate = 0
        .appendRune(cast(rune, unit >= 0xDC00 and unit <= 0xDFFF ? 0xFFFD : unit))
    }

    mtd appendRune(value: rune)
    {
        if .state.skip or .state.hidden do
            return
        var encoded: String
        encoded.append(value)
        .appendText(encoded)
    }

    mtd appendText(value: string)
    {
        if .state.skip or .state.hidden do
            return
        .syncStyle()
        Package.appendHtmlEscaped(&.paragraph, value)
    }

    mtd appendHtml(value: string)
    {
        if .state.skip or .state.hidden do
            return
        .syncStyle()
        .paragraph += value
    }

    mtd syncStyle()
    {
        if .shown.bold == .state.bold and .shown.italic == .state.italic and
           .shown.underline == .state.underline and .shown.strike == .state.strike do
            return
        .closeStyle()
        if .state.bold do
            .paragraph += "<b>"
        if .state.italic do
            .paragraph += "<i>"
        if .state.underline do
            .paragraph += "<u>"
        if .state.strike do
            .paragraph += "<s>"
        .shown = .state
    }

    mtd closeStyle()
    {
        if .shown.strike do
            .paragraph += "</s>"
        if .shown.underline do
            .paragraph += "</u>"
        if .shown.italic do
            .paragraph += "</i>"
        if .shown.bold do
            .paragraph += "</b>"
        .shown = {}
    }

    mtd finishParagraph(force: bool)
    {
        .closeStyle()
        if .paragraph.isEmpty() and not force do
            return
        .document.html += "<p"
        switch .alignment
        {
        case .Center:  .document.html += " style=\"text-align:center\""
        case .Right:   .document.html += " style=\"text-align:right\""
        case .Justify: .document.html += " style=\"text-align:justify\""
        }
        .document.html += ">"
        .document.html += .paragraph.isEmpty() ? "<br>" : .paragraph.toString()
        .document.html += "</p>"
        .paragraph.clear()
        .document.paragraphs += 1
    }

    mtd finishCell()
    {
        .closeStyle()
        .document.html += "<td>"
        .document.html += .paragraph.isEmpty() ? "<br>" : .paragraph.toString()
        .document.html += "</td>"
        .paragraph.clear()
        .rowHasCell = true
        .document.paragraphs += 1
    }

    mtd finishRow()
    {
        if not .paragraph.isEmpty() or not .rowHasCell do
            .finishCell()
        .document.html += "</tr></table>"
        .tableOpen = false
        .rowHasCell = false
    }

    func hexDigit(value: u8)->s32
    {
        if value >= '0' and value <= '9' do
            return cast(s32, value - '0')
        if value >= 'a' and value <= 'f' do
            return cast(s32, value - 'a') + 10
        if value >= 'A' and value <= 'F' do
            return cast(s32, value - 'A') + 10
        return -1
    }
}
