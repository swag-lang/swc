#global internal
#global namespace Viewers.Rtf

using Core

// The formatted, bounded body of one Rich Text Format document.
struct Document
{
    html:             String
    paragraphs:       u64
    images:           u64
    omittedObjects:   u64
    simplifiedStyles: bool
    paper:            bool
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
    font:            u32 = Swag.U32.Max
    size:            u32 = 24
    color:           u32 = Swag.U32.Max
    highlight:       u32 = Swag.U32.Max
    alignment:       Alignment
    before:          s32 = -1
    after:           s32 = -1
    left:            s32
    right:           s32
    first:           s32
    line:            s32
    multipleLine:    bool
    bold:            bool
    italic:          bool
    underline:       bool
    strike:          bool
    hidden:          bool
    skip:            bool
    ignorable:       bool
    shapePicture:    bool
    unicodeFallback: u32 = 1
}

private struct Reader
{
    bytes:               Array'u8
    offset:              u64
    groups:              Array'State
    state:               State
    shown:               State
    fonts:               Array'Font
    colors:              Array'String
    defaultFont:         u32 = Swag.U32.Max
    shownSpan:           bool
    paragraph:           String
    document:            Document
    sawHeader:           bool
    tableOpen:           bool
    rowHasCell:          bool
    highSurrogate:       u32
    imageBytes:          u64
    skipFallbackPicture: bool
}

impl Document
{
    mtd const details()->String
    {
        var result = Format.toString(texts().ui_Details, .paragraphs)
        if .images do
            result += .images == 1 ? String.from(texts().ui_OneImage) : Format.toString(texts().ui_Images, .images)
        if .omittedObjects do
            result += .omittedObjects == 1 ? String.from(texts().ui_OneOmitted) : Format.toString(texts().ui_Omitted, .omittedObjects)
        if .simplifiedStyles do
            result += texts().ui_StylesSimplified
        return result
    }

    // Parses RTF and bounded raster pictures without executing fields or loading linked resources.
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
                if .groups.count == 1
                {
                    if .tableOpen do
                        .finishRow()
                    if not .paragraph.isEmpty() do
                        .finishParagraph(force: false)
                }

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
                      .bytes[.offset] != '{' and
                      .bytes[.offset] != '}' and
                      .bytes[.offset] != '\\' and
                      .bytes[.offset] != '\r' and
                      .bytes[.offset] != '\n' do
                    .offset += 1
                if not .state.skip and not .state.hidden and not .state.ignorable do
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
        var bodyStyle: String = " style=\"padding:24px;box-sizing:border-box;"
        if .document.paper do
            bodyStyle += "background-color:#FFFFFF;color:#202024;"
        bodyStyle += "\""
        .document.html.insert("<html><body".count, bodyStyle)
        return #move .document
    }

    mtd control() fail
    {
        let start   = .offset + 1
        let control = try Control.parse(.bytes.toSlice(), .offset)
        .offset = control.end
        let symbol = control.symbol
        if symbol
        {
            if .state.ignorable and symbol != '*'
            {
                .state.ignorable = false
                .state.skip      = true
            }

            switch symbol
            {
            case '\\', '{', '}':
                .appendRune(cast(rune, symbol))

            case '~':
                .appendRune(0xA0)

            case '-':
                .appendRune(0xAD)

            case '_':
                .appendRune(0x2011)

            case '*':
                .state.ignorable = true

            case '\'':
                if .offset + 2 > .bytes.count do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                let first  = .hexDigit(.bytes[.offset])
                let second = .hexDigit(.bytes[.offset + 1])
                if first < 0 or second < 0 do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                .offset += 2
                var encoded: [1] u8 = [cast(u8, first * 16 + second)]
                .appendText(Text.decode(encoded, .Windows1252))
            }

            return
        }

        let word      = control.word
        let number    = control.number
        let hasNumber = control.hasNumber

        if .state.ignorable
        {
            .state.ignorable = false
            if word != "shppict" do
                .state.skip = true
        }

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
        case "fonttbl", "colortbl":
            let table = try Catalog.parse(.bytes.toSlice(), .offset, .groups.count, word == "fonttbl")
            .offset = table.end
            .document.simplifiedStyles = .document.simplifiedStyles or table.limited
            if word == "fonttbl" do
                .fonts = table.fonts
            else do
                .colors = table.colors
            .state.skip = true

        case "deff":
            if hasNumber and number >= 0
            {
                .defaultFont = cast(u32, number)
                .state.font  = .defaultFont
            }

        case "f":
            if hasNumber and number >= 0 do
                .state.font = cast(u32, number)

        case "fs":
            if hasNumber and number >= 1 and number <= 800 do
                .state.size = cast(u32, number)
            else do
                .document.simplifiedStyles = true

        case "cf", "highlight":
            if hasNumber and number >= 0 and cast(u64, number) < .colors.count
            {
                if word == "cf" do
                    .state.color = cast(u32, number)
                else do
                    .state.highlight = cast(u32, number)
                if not .colors[cast(u64, number)].isEmpty() do
                    .document.paper = true
            }
            else
            {
                .document.simplifiedStyles = true
                if word == "cf" do
                    .state.color = Swag.U32.Max
                else do
                    .state.highlight = Swag.U32.Max
            }

        case "sb", "sa", "li", "ri", "fi", "sl":
            if hasNumber and number >= -31680 and number <= 31680
            {
                switch word
                {
                case "sb": .state.before = Math.max(number, 0)
                case "sa": .state.after = Math.max(number, 0)
                case "li": .state.left = number
                case "ri": .state.right = number
                case "fi": .state.first = number
                case "sl": .state.line = number
                }
            }
            else
            {
                .document.simplifiedStyles = true
            }

        case "slmult":
            .state.multipleLine = number == 1

        case "s", "cs", "ds", "ts":
            if hasNumber and number != 0 do
                .document.simplifiedStyles = true

        case "stylesheet", "info", "generator", "filetbl", "listtable", "listoverridetable",
             "xmlnstbl", "datastore", "themedata", "colorschememapping", "header", "headerl",
             "headerr", "footer", "footerl", "footerr", "footnote", "annotation", "fldinst":
            .state.skip = true

        case "shppict":
            .state.shapePicture = true

        case "nonshppict":
            if .skipFallbackPicture do
                .state.skip = true
            .skipFallbackPicture = false

        case "pict":
            if not .state.hidden
            {
                let picture = try Picture.parse(.bytes.toSlice(), .offset, .groups.count)
                .offset = picture.end
                if picture.html.isEmpty() or .imageBytes + picture.encodedBytes > 8 * 1024 * 1024
                {
                    .document.omittedObjects += 1
                    .appendText(texts().ui_ImageOmitted)
                }
                else
                {
                    .appendHtml(picture.html)
                    .document.images     += 1
                    .imageBytes          += picture.encodedBytes
                    .skipFallbackPicture = .state.shapePicture
                }
            }

            .state.skip = true

        case "object":
            .document.omittedObjects += 1
            .appendText(texts().ui_ObjectOmitted)
            .state.skip = true

        case "b":
            .state.bold = not hasNumber or number != 0

        case "i":
            .state.italic = not hasNumber or number != 0

        case "ul":
            .state.underline = not hasNumber or number != 0

        case "ulnone":
            .state.underline = false

        case "strike":
            .state.strike = not hasNumber or number != 0

        case "v":
            .state.hidden = not hasNumber or number != 0

        case "plain":
            .state.bold      = false
            .state.italic    = false
            .state.underline = false
            .state.strike    = false
            .state.hidden    = false
            .state.font      = .defaultFont
            .state.size      = 24
            .state.color     = Swag.U32.Max
            .state.highlight = Swag.U32.Max

        case "ql":
            .state.alignment = .Left

        case "qc":
            .state.alignment = .Center

        case "qr":
            .state.alignment = .Right

        case "qj":
            .state.alignment = .Justify

        case "pard":
            .state.alignment    = .Left
            .state.before       = 0
            .state.after        = 0
            .state.left         = 0
            .state.right        = 0
            .state.first        = 0
            .state.line         = 0
            .state.multipleLine = false

        case "par":
            if .tableOpen do
                .appendHtml("<br>")
            else do
                .finishParagraph(force: true)

        case "line":
            .appendHtml("<br>")

        case "tab":
            .appendHtml("&emsp;")

        case "page":
            .finishParagraph(force: false)
            .document.html += "<hr>"

        case "trowd":
            if .tableOpen do
                .finishRow()
            .finishParagraph(force: false)
            .document.html += "<table><tr>"
            .tableOpen     = true
            .rowHasCell    = false

        case "cell":
            if .tableOpen do
                .finishCell()

        case "row":
            if .tableOpen do
                .finishRow()

        case "bullet":
            .appendRune(0x2022)

        case "emdash":
            .appendRune(0x2014)

        case "endash":
            .appendRune(0x2013)

        case "lquote":
            .appendRune(0x2018)

        case "rquote":
            .appendRune(0x2019)

        case "ldblquote":
            .appendRune(0x201C)

        case "rdblquote":
            .appendRune(0x201D)
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
            elif .bytes[.offset] != '{' and .bytes[.offset] != '}'
            {
                .offset += 1
            }
            else
            {
                break
            }

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
        for byte in value where byte != ' 'u8 and byte != '\t'u8 and byte != '\r'u8 and byte != '\n'u8 do
            .skipFallbackPicture = false
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
        if .shown.bold == .state.bold and
           .shown.italic == .state.italic and
           .shown.underline == .state.underline and
           .shown.strike == .state.strike and
           .shown.font == .state.font and
           .shown.size == .state.size and
           .shown.color == .state.color and
           .shown.highlight == .state.highlight do
            return
        .closeStyle()
        var css: String
        if .state.size != 24 do
            css += Format.toString("font-size:%pt;", cast(f64, .state.size) / 2)
        if .state.font != Swag.U32.Max
        {
            var found = false
            for font in .fonts where font.id == .state.font
            {
                css   += Format.toString("font-family:'%';", font.family)
                found = true
                break
            }

            if not found do
                .document.simplifiedStyles = true
        }

        if .state.color < .colors.count and not .colors[.state.color].isEmpty() do
            css += Format.toString("color:#%;", .colors[.state.color])
        if .state.highlight < .colors.count and not .colors[.state.highlight].isEmpty() do
            css += Format.toString("background-color:#%;", .colors[.state.highlight])
        if not css.isEmpty()
        {
            .paragraph += Format.toString("<span style=\"%\">", css)
            .shownSpan = true
        }

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
        if .shownSpan do
            .paragraph += "</span>"
        .shownSpan = false
        .shown     = {}
    }

    mtd finishParagraph(force: bool)
    {
        .closeStyle()
        if .paragraph.isEmpty() and not force do
            return
        .document.html += "<p"
        var css: String
        switch .state.alignment
        {
        case .Center:  css += "text-align:center;"
        case .Right:   css += "text-align:right;"
        case .Justify: css += "text-align:justify;"
        }

        if .state.before >= 0 do
            css += Format.toString("margin-top:%pt;", cast(f64, .state.before) / 20)
        if .state.after >= 0 do
            css += Format.toString("margin-bottom:%pt;", cast(f64, .state.after) / 20)
        if .state.left do
            css += Format.toString("margin-left:%pt;", cast(f64, .state.left) / 20)
        if .state.right do
            css += Format.toString("margin-right:%pt;", cast(f64, .state.right) / 20)
        if .state.first do
            css += Format.toString("text-indent:%pt;", cast(f64, .state.first) / 20)
        if .state.line
        {
            if .state.multipleLine do
                css += Format.toString("line-height:%;", Math.abs(cast(f64, .state.line)) / 240)
            else do
                css += Format.toString("line-height:%pt;", Math.abs(cast(f64, .state.line)) / 20)
        }

        if not css.isEmpty()
        {
            css.removeBack(1)
            .document.html += Format.toString(" style=\"%\"", css)
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
        .tableOpen     = false
        .rowHasCell    = false
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
