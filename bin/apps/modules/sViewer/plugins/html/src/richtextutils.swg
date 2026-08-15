#global internal

using Core

func viewerRichDecodedEntity(source: string, start: u64)->{ value: String, eat: u64 }
{
    var result: retval
    result.value = "&"
    result.eat   = 1
    if start >= @countof(source) or source[start] != '&' do
        return result

    let close = Utf8.indexOf(source, ';'rune, start + 1)
    if close == Swag.U64.Max or close - start > 12 do
        return result

    let entity = source[start + 1 until close]
    switch entity
    {
    case "amp":
        result.value = "&"

    case "lt":
        result.value = "‹"

    case "gt":
        result.value = "›"

    case "quot":
        result.value = "\""

    case "apos":
        result.value = "'"

    case "nbsp":
        result.value = " "

    case "ndash":
        result.value = "–"

    case "mdash":
        result.value = "—"

    case "hellip":
        result.value = "…"

    case "bull":
        result.value = "•"

    case "copy":
        result.value = "©"

    case "reg":
        result.value = "®"

    case "trade":
        result.value = "™"

    default:
        if @countof(entity) < 2 or entity[0] != '#' do
            return result

        let hexadecimal = @countof(entity) > 2 and (entity[1] == 'x' or entity[1] == 'X')
        let digits      = hexadecimal ? entity[2 to] : entity[1 to]
        var number: u64
        if hexadecimal
        {
            let parsed = catch StrConv.parseX64(digits) as parseError
            if parseError != null or parsed.ovf or parsed.eat != @countof(digits) do
                return result
            number = parsed.value
        }
        else
        {
            let parsed = catch StrConv.parseU64(digits) as parseError
            if parseError != null or parsed.ovf or parsed.eat != @countof(digits) do
                return result
            number = parsed.value
        }

        let character = cast(rune) number
        if !Utf8.isValidRune(character) do
            return result
        result.value.clear()
        if character == '<' do
            result.value = "‹"
        elif character == '>' do
            result.value = "›"
        else do
            result.value.append(character)
    }

    result.eat = close - start + 1
    return result
}

func viewerDecodedEntity(source: string, start: u64)->{ value: String, eat: u64 } => viewerRichDecodedEntity(source, start)

func viewerRichText(text: string, decodeEntities = false)->String
{
    var result: retval
    var index = 0'u64
    while index < @countof(text)
    {
        if decodeEntities and text[index] == '&'
        {
            let entity = viewerRichDecodedEntity(text, index)
            result += entity.value
            index  += entity.eat
            continue
        }

        if text[index] == '<' do
            result += "‹"
        elif text[index] == '>' do
            result += "›"
        else do
            result += text[index]
        index += 1
    }

    return result
}
