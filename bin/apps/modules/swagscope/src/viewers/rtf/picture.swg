#global internal
#global namespace Viewers.Rtf

using Core

// A single bounded raster picture decoded from an RTF destination.
struct Picture
{
    html:         String
    end:          u64
    encodedBytes: u64
}

impl Picture
{
    // Stops before the current destination's closing brace; nested metadata never becomes pixels.
    func parse(source: const [..] u8, start: u64, parentDepth: u64)->Picture fail
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

        var result:    #returntype
        var at                = start
        var depth             = 0'u64
        var data:      Array'u8
        var mediaType: string = ""
        var supported         = true
        var nibble            = -1's32
        var width             = 0's32
        var height            = 0's32
        var scaleX            = 100's32
        var scaleY            = 100's32
        while at < source.count
        {
            let value = source[at]
            if value == '}'
            {
                if not depth
                {
                    result.end = at
                    if nibble >= 0 do
                        supported = false
                    if supported and data.count
                    {
                        let pixelsX = cast(s64, width) * scaleX / 1500
                        let pixelsY = cast(s64, height) * scaleY / 1500
                        if width >= 0 and
                           height >= 0 and
                           scaleX > 0 and
                           scaleY > 0 and
                           pixelsX >= 0 and
                           pixelsY >= 0 and
                           pixelsX <= 4096 and
                           pixelsY <= 4096 and
                           ((width == 0 and height == 0) or (pixelsX > 0 and pixelsY > 0))
                        {
                            result.html = Package.embeddedImageHtml(data.toSlice(), mediaType, cast(u32, pixelsX), cast(u32, pixelsY), texts().ui_ImageDescription)
                            if not result.html.isEmpty() do
                                result.encodedBytes = data.count
                        }
                    }

                    return result
                }

                depth -= 1
                at    += 1
            }
            elif value == '{'
            {
                depth += 1
                if parentDepth + depth > 128 do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                at += 1
            }
            elif value == '\\'
            {
                at += 1
                if at >= source.count do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                let symbol = source[at]
                if not Latin1.isLetter(symbol)
                {
                    at += 1

                    // Escaped byte data is accepted alongside the usual hexadecimal stream.
                    if symbol == '\''
                    {
                        if at + 2 > source.count do
                            fail Errors.InvalidFormatError{texts().err_Invalid}
                        let high = digit(source[at])
                        let low  = digit(source[at + 1])
                        if high < 0 or low < 0
                        {
                            supported = false
                        }
                        elif not depth and supported
                        {
                            if nibble >= 0 do
                                supported = false
                            else do
                                data.add(cast(u8, high * 16 + low))
                        }

                        at += 2
                    }

                    if data.count > 2 * 1024 * 1024
                    {
                        supported = false
                        data.clear()
                    }

                    continue
                }

                let wordStart = at
                while at < source.count and Latin1.isLetter(source[at]) do
                    at += 1
                let word      = cast(string, source[wordStart until at])
                var number    = 0's32
                var hasNumber = false
                var negative  = false
                if at < source.count and source[at] == '-'
                {
                    negative = true
                    at       += 1
                }

                while at < source.count and Latin1.isDigit(source[at])
                {
                    hasNumber = true
                    if number > 100_000_000 do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    number = number * 10 + cast(s32, source[at] - '0')
                    at     += 1
                }

                if negative do
                    number = -number
                if at < source.count and source[at] == ' ' do
                    at += 1
                if word == "bin"
                {
                    if not hasNumber or number < 0 or cast(u64, number) > source.count - at do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    let count = cast(u64, number)
                    if not depth and supported
                    {
                        if nibble >= 0 or data.count + count > 2 * 1024 * 1024 do
                            supported = false
                        else do
                            data.add(source[at until at + count])
                    }

                    at += count
                }
                elif not depth
                {
                    if not hasNumber and
                       (word == "picwgoal" or
                        word == "pichgoal" or
                        word == "picscalex" or
                        word == "picscaley") do
                        supported = false
                    switch word
                    {
                    case "pngblip":
                        if mediaType.count and mediaType != "image/png" do
                            supported = false
                        mediaType = "image/png"

                    case "jpegblip":
                        if mediaType.count and mediaType != "image/jpeg" do
                            supported = false
                        mediaType = "image/jpeg"

                    case "picwgoal":
                        width = number

                    case "pichgoal":
                        height = number

                    case "picscalex":
                        scaleX = number

                    case "picscaley":
                        scaleY = number
                    }
                }
            }
            else
            {
                at += 1
                if not depth and
                   value != ' ' and
                   value != '\t' and
                   value != '\r' and
                   value != '\n' and
                   supported
                {
                    let hex = digit(value)
                    if hex < 0
                    {
                        supported = false
                    }
                    elif nibble < 0
                    {
                        nibble = hex
                    }
                    else
                    {
                        data.add(cast(u8, nibble * 16 + hex))
                        nibble = -1
                    }
                }
            }

            if data.count > 2 * 1024 * 1024
            {
                supported = false
                data.clear()
            }
        }

        fail Errors.InvalidFormatError{texts().err_Invalid}
    }
}
