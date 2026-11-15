#global internal
#global namespace Viewers.Rtf

using Core

struct Font
{
    id:     u32
    family: String
}

// A bounded font or color table, ending before the enclosing destination's closing brace.
struct Catalog
{
    fonts:   Array'Font
    colors:  Array'String
    end:     u64
    limited: bool
}

impl Catalog
{
    func parse(source: const [..] u8, start, parentDepth: u64, fontTable: bool)->Catalog fail
    {
        func digit(value: u8)->s32
        {
            if value >= '0' and value <= '9' do
                return cast(s32, value - '0')
            if value >= 'a' and value <= 'f' do
                return cast(s32, value - 'a') + 10
            if value >= 'A' and value <= 'F' do
                return cast(s32, value - 'A') + 10
            return -1
        }

        var result:  #returntype
        var at              = start
        var depth           = 0'u64
        var fontId          = Swag.U32.Max
        var name:    String
        var red, green, blue: s32
        var hasColor        = false
        var skip:    bool
        var skipped: Array'bool
        var unicodeFallback = 1'u64
        while at < source.count
        {
            if at - start > 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            let value = source[at]
            if value == '}'
            {
                if not depth
                {
                    name.trim()
                    result.end     = at
                    result.limited = result.limited or not name.isEmpty() or hasColor
                    return result
                }

                skip  = skipped.popBack()
                depth -= 1
                at    += 1
            }
            elif value == '{'
            {
                depth += 1
                if parentDepth + depth > 128 do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                skipped.add(skip)
                at += 1
            }
            elif value == '\\'
            {
                let control = try Control.parse(source, at)
                at = control.end
                if control.word == "bin"
                {
                    if not control.hasNumber or
                       control.number < 0 or
                       cast(u64, control.number) > source.count - at do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    at += cast(u64, control.number)
                    continue
                }

                if control.symbol == '\''
                {
                    if at + 2 > source.count do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    let high = digit(source[at])
                    let low  = digit(source[at + 1])
                    if high < 0 or low < 0 do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    if fontTable and not skip
                    {
                        var encoded = [cast(u8, high * 16 + low)]
                        name += Text.decode(encoded, .Windows1252)
                    }

                    at += 2
                    continue
                }

                if control.symbol == '*' or control.word == "falt" or control.word == "fname" do
                    skip = true
                if skip do
                    continue
                if fontTable
                {
                    if control.word == "f" and control.hasNumber and control.number >= 0
                    {
                        fontId = cast(u32, control.number)
                        name.clear()
                    }
                    elif control.word == "uc" and
                         control.hasNumber and
                         control.number >= 0 and
                         control.number <= 16
                    {
                        unicodeFallback = cast(u64, control.number)
                    }
                    elif control.word == "u" and
                         control.hasNumber and
                         control.number >= -32768 and
                         control.number <= 32767
                    {
                        let unit = cast(u32, control.number < 0 ? control.number + 65536 : control.number)
                        if unit < 0xD800 or unit > 0xDFFF do
                            name.append(cast(rune, unit))
                        else do
                            result.limited = true
                        var remaining = unicodeFallback
                        while remaining and at < source.count and source[at] != '{' and source[at] != '}'
                        {
                            if source[at] == '\\' and at + 1 < source.count
                            {
                                let escaped = try Control.parse(source, at)
                                at = escaped.end
                                if escaped.symbol == '\''
                                {
                                    if at + 2 > source.count do
                                        fail Errors.InvalidFormatError{texts().err_Invalid}
                                    at += 2
                                }
                            }
                            else
                            {
                                at += 1
                            }

                            remaining -= 1
                        }
                    }
                    elif control.symbol == '\\' or control.symbol == '{' or control.symbol == '}'
                    {
                        name += control.symbol
                    }
                }
                elif control.word == "red" or control.word == "green" or control.word == "blue"
                {
                    if not control.hasNumber or control.number < 0 or control.number > 255 do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    if control.word == "red" do
                        red = control.number
                    elif control.word == "green" do
                        green = control.number
                    else do
                        blue = control.number
                    hasColor = true
                }
            }
            else
            {
                at += 1
                if skip do
                    continue
                if value == ';'
                {
                    if fontTable
                    {
                        name.trim()
                        let family = name.toString()
                        var safe   = family.count <= 256 and family.count != 0
                        for byte in family where byte < 128 and
                                                 not Latin1.isLetterOrDigit(byte) and
                                                 byte != ' 'u8 and
                                                 byte != '-'u8 and
                                                 byte != '.'u8 do
                            safe = false
                        if fontId != Swag.U32.Max and safe do
                            result.fonts.add(Font{fontId, String.from(family)})
                        else do
                            result.limited = true
                        name.clear()
                        fontId = Swag.U32.Max
                    }
                    else
                    {
                        result.colors.add(hasColor ? Format.toString("%{X02}%{X02}%{X02}", red, green, blue) : String{})
                        red      = 0
                        green    = 0
                        blue     = 0
                        hasColor = false
                    }

                    if result.fonts.count > 1024 or result.colors.count > 4096 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }
                elif fontTable and value != '\r' and value != '\n'
                {
                    var encoded = [value]
                    name += Text.decode(encoded, .Windows1252)
                    if name.count > 256 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }
            }
        }

        fail Errors.InvalidFormatError{texts().err_Invalid}
    }
}
