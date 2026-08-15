using Core, Pixel

struct HtmlCssStyle
{
    color:      Color
    background: Color
    fontSize:   f32
    maxWidth:   f32
    bold:       bool
    italic:     bool
    align:      StringHorzAlignment = .Left
    hasAlign:   bool
}

struct HtmlCssRule
{
    selector:     String
    declarations: String
}

private func htmlCssColor(value: string)->Color
{
    let trimmed = Latin1.trim(value)
    if @countof(trimmed) == 7 and trimmed[0] == '#'
    {
        let parsed = catch StrConv.parseX64(trimmed[1 to]) as parseError
        if parseError == null and !parsed.ovf and parsed.eat == 6 do
            return Color.fromArgb(0xFF000000'u32 | cast(u32) parsed.value)
    }
    if @countof(trimmed) == 4 and trimmed[0] == '#'
    {
        let parsed = catch StrConv.parseX64(trimmed[1 to]) as parseError
        if parseError == null and !parsed.ovf and parsed.eat == 3
        {
            let r = cast(u8) ((parsed.value >> 8) & 0xF) * 17
            let g = cast(u8) ((parsed.value >> 4) & 0xF) * 17
            let b = cast(u8) (parsed.value & 0xF) * 17
            return Color.fromArgb(255, r, g, b)
        }
    }

    switch trimmed
    {
    case "black":       return Argb.Black
    case "white":       return Argb.White
    case "red":         return Argb.Red
    case "green":       return Argb.Green
    case "blue":        return Argb.Blue
    case "gray", "grey": return Argb.Gray
    case "yellow":      return Argb.Yellow
    case "orange":      return Argb.Orange
    case "purple":      return Argb.Purple
    case "tomato":      return Argb.Tomato
    case "transparent": return Argb.Zero
    }
    return {}
}

private func htmlCssSize(value: string, rootSize = 16'f32)->f32
{
    let trimmed = Latin1.trim(value)
    let parsed  = catch StrConv.parseF64(trimmed) as parseError
    if parseError != null or parsed.ovf or parsed.eat == 0 do
        return 0
    let suffix = Latin1.trim(trimmed[parsed.eat to])
    if suffix == "em" or suffix == "rem" do
        return cast(f32) parsed.value * rootSize
    if suffix == "%" do
        return cast(f32) parsed.value * rootSize / 100
    return cast(f32) parsed.value
}

private func applyHtmlDeclarations(style: *HtmlCssStyle, declarations: string)
{
    for raw in Tokenize.split(declarations, ';'u8)
    {
        let colon = Utf8.indexOf(raw, ':'rune)
        if colon == Swag.U64.Max do
            continue
        let name  = String.from(Latin1.trim(raw[0 until colon])).toLower()
        let value = String.from(Latin1.trim(raw[colon + 1 to])).toLower()
        switch name.toString()
        {
        case "color":
            let color = htmlCssColor(value.toString())
            if color.a do
                style.color = color
        case "background", "background-color":
            let color = htmlCssColor(value.toString())
            if color.a do
                style.background = color
        case "font-size": style.fontSize = htmlCssSize(value.toString())
        case "max-width": style.maxWidth = htmlCssSize(value.toString())
        case "font-weight": style.bold = value == "bold" or value == "600" or value == "700" or value == "800" or value == "900"
        case "font-style": style.italic = value == "italic" or value == "oblique"
        case "text-align":
            style.hasAlign = true
            switch value.toString()
            {
            case "center": style.align = .Center
            case "right", "end": style.align = .Right
            default: style.align = .Left
            }
        }
    }
}

func parseHtmlCss(source: string)->Array'HtmlCssRule
{
    var result: retval
    var scan = 0'u64
    while scan < @countof(source)
    {
        let styleStart = Utf8.indexOf(source, "<style", scan, .Latin1NoCase)
        if styleStart == Swag.U64.Max do
            break
        let openEnd = Utf8.indexOf(source, '>'rune, styleStart + 6)
        if openEnd == Swag.U64.Max do
            break
        let styleEnd = Utf8.indexOf(source, "</style", openEnd + 1, .Latin1NoCase)
        if styleEnd == Swag.U64.Max do
            break

        let css = source[openEnd + 1 until styleEnd]
        var pos = 0'u64
        while pos < @countof(css)
        {
            let brace = Utf8.indexOf(css, '{'rune, pos)
            if brace == Swag.U64.Max do
                break
            let close = Utf8.indexOf(css, '}'rune, brace + 1)
            if close == Swag.U64.Max do
                break
            let declarations = String.from(css[brace + 1 until close])
            for selector in Tokenize.split(css[pos until brace], ','u8)
            {
                let clean = Latin1.trim(selector)
                if @countof(clean) and !Utf8.startsWith(clean, "@") do
                    result.add(HtmlCssRule{String.from(clean), declarations})
            }
            pos = close + 1
        }
        scan = styleEnd + 7
    }
    return result
}

private func htmlLastSimpleSelector(selector: string)->string
{
    var start = 0'u64
    for value, index in selector
    {
        if value == ' ' or value == '>' do
            start = index + 1
    }
    return Latin1.trim(selector[start to])
}

private func htmlCssMatches(selector, tagName, tag: string)->bool
{
    var simple = htmlLastSimpleSelector(selector)
    let pseudo = Utf8.indexOf(simple, ':'rune)
    if pseudo != Swag.U64.Max do
        simple = simple[0 until pseudo]
    if !@countof(simple) or simple == "*" do
        return true

    let idName    = htmlAttribute(tag, "id")
    let className = htmlAttribute(tag, "class")
    if simple[0] == '#' do
        return idName == simple[1 to]
    if simple[0] == '.'
    {
        for classPart in Tokenize.split(className.toString(), ' 'u8) where classPart == simple[1 to] do
            return true
        return false
    }

    let dot = Utf8.indexOf(simple, '.'rune)
    if dot != Swag.U64.Max
    {
        if Utf8.compare(simple[0 until dot], tagName, .Latin1NoCase) != 0 do
            return false
        for classPart in Tokenize.split(className.toString(), ' 'u8) where classPart == simple[dot + 1 to] do
            return true
        return false
    }
    return Utf8.compare(simple, tagName, .Latin1NoCase) == 0
}

func htmlCssStyle(tag, tagName: string, rules: const [..] HtmlCssRule)->HtmlCssStyle
{
    var result: retval
    for rule in rules where htmlCssMatches(rule.selector.toString(), tagName, tag) do
        applyHtmlDeclarations(&result, rule.declarations.toString())
    applyHtmlDeclarations(&result, htmlAttribute(tag, "style").toString())
    return result
}
