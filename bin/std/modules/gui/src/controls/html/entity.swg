#global internal

using Core

// One decoded HTML character reference.
//
// `eat` is the number of source bytes the reference occupies, and is zero when the text at the
// requested position is not a reference at all. A handful of named references expand to two code
// points, so `second` completes `first` when it is not zero.
struct HtmlEntity
{
    first:  rune
    second: rune
    eat:    u64
}

// Maps a named character reference to its code points, without the leading `&` and the
// trailing `;`.
//
// The set covers the references a document actually carries: the five XML ones, the typographic
// and currency marks, the Latin-1 letters, the Greek alphabet, and the arrows and operators a
// technical page uses. An unlisted name is left as literal text, which is what a browser does
// with an unresolvable reference.
private func htmlNamedEntity(name: string)->HtmlEntity
{
    var result: retval
    switch name
    {
    case "amp":      result.first = '&'
    case "lt":       result.first = '<'
    case "gt":       result.first = '>'
    case "quot":     result.first = '"'
    case "apos":     result.first = '\''
    case "nbsp":     result.first = ' '
    case "iexcl":    result.first = '¡'
    case "cent":     result.first = '¢'
    case "pound":    result.first = '£'
    case "curren":   result.first = '¤'
    case "yen":      result.first = '¥'
    case "brvbar":   result.first = '¦'
    case "sect":     result.first = '§'
    case "uml":      result.first = '¨'
    case "copy":     result.first = '©'
    case "ordf":     result.first = 'ª'
    case "laquo":    result.first = '«'
    case "not":      result.first = '¬'
    case "shy":      result.first = '­'
    case "reg":      result.first = '®'
    case "macr":     result.first = '¯'
    case "deg":      result.first = '°'
    case "plusmn":   result.first = '±'
    case "sup2":     result.first = '²'
    case "sup3":     result.first = '³'
    case "acute":    result.first = '´'
    case "micro":    result.first = 'µ'
    case "para":     result.first = '¶'
    case "middot":   result.first = '·'
    case "cedil":    result.first = '¸'
    case "sup1":     result.first = '¹'
    case "ordm":     result.first = 'º'
    case "raquo":    result.first = '»'
    case "frac14":   result.first = '¼'
    case "frac12":   result.first = '½'
    case "frac34":   result.first = '¾'
    case "iquest":   result.first = '¿'
    case "Agrave":   result.first = 'À'
    case "Aacute":   result.first = 'Á'
    case "Acirc":    result.first = 'Â'
    case "Atilde":   result.first = 'Ã'
    case "Auml":     result.first = 'Ä'
    case "Aring":    result.first = 'Å'
    case "AElig":    result.first = 'Æ'
    case "Ccedil":   result.first = 'Ç'
    case "Egrave":   result.first = 'È'
    case "Eacute":   result.first = 'É'
    case "Ecirc":    result.first = 'Ê'
    case "Euml":     result.first = 'Ë'
    case "Igrave":   result.first = 'Ì'
    case "Iacute":   result.first = 'Í'
    case "Icirc":    result.first = 'Î'
    case "Iuml":     result.first = 'Ï'
    case "ETH":      result.first = 'Ð'
    case "Ntilde":   result.first = 'Ñ'
    case "Ograve":   result.first = 'Ò'
    case "Oacute":   result.first = 'Ó'
    case "Ocirc":    result.first = 'Ô'
    case "Otilde":   result.first = 'Õ'
    case "Ouml":     result.first = 'Ö'
    case "times":    result.first = '×'
    case "Oslash":   result.first = 'Ø'
    case "Ugrave":   result.first = 'Ù'
    case "Uacute":   result.first = 'Ú'
    case "Ucirc":    result.first = 'Û'
    case "Uuml":     result.first = 'Ü'
    case "Yacute":   result.first = 'Ý'
    case "THORN":    result.first = 'Þ'
    case "szlig":    result.first = 'ß'
    case "agrave":   result.first = 'à'
    case "aacute":   result.first = 'á'
    case "acirc":    result.first = 'â'
    case "atilde":   result.first = 'ã'
    case "auml":     result.first = 'ä'
    case "aring":    result.first = 'å'
    case "aelig":    result.first = 'æ'
    case "ccedil":   result.first = 'ç'
    case "egrave":   result.first = 'è'
    case "eacute":   result.first = 'é'
    case "ecirc":    result.first = 'ê'
    case "euml":     result.first = 'ë'
    case "igrave":   result.first = 'ì'
    case "iacute":   result.first = 'í'
    case "icirc":    result.first = 'î'
    case "iuml":     result.first = 'ï'
    case "eth":      result.first = 'ð'
    case "ntilde":   result.first = 'ñ'
    case "ograve":   result.first = 'ò'
    case "oacute":   result.first = 'ó'
    case "ocirc":    result.first = 'ô'
    case "otilde":   result.first = 'õ'
    case "ouml":     result.first = 'ö'
    case "divide":   result.first = '÷'
    case "oslash":   result.first = 'ø'
    case "ugrave":   result.first = 'ù'
    case "uacute":   result.first = 'ú'
    case "ucirc":    result.first = 'û'
    case "uuml":     result.first = 'ü'
    case "yacute":   result.first = 'ý'
    case "thorn":    result.first = 'þ'
    case "yuml":     result.first = 'ÿ'
    case "OElig":    result.first = 'Œ'
    case "oelig":    result.first = 'œ'
    case "Scaron":   result.first = 'Š'
    case "scaron":   result.first = 'š'
    case "Yuml":     result.first = 'Ÿ'
    case "fnof":     result.first = 'ƒ'
    case "circ":     result.first = 'ˆ'
    case "tilde":    result.first = '˜'
    case "ensp":     result.first = ' '
    case "emsp":     result.first = ' '
    case "thinsp":   result.first = ' '
    case "zwnj":     result.first = '‌'
    case "zwj":      result.first = '‍'
    case "lrm":      result.first = '‎'
    case "rlm":      result.first = '‏'
    case "ndash":    result.first = '–'
    case "mdash":    result.first = '—'
    case "horbar":   result.first = '―'
    case "lsquo":    result.first = '‘'
    case "rsquo":    result.first = '’'
    case "sbquo":    result.first = '‚'
    case "ldquo":    result.first = '“'
    case "rdquo":    result.first = '”'
    case "bdquo":    result.first = '„'
    case "dagger":   result.first = '†'
    case "Dagger":   result.first = '‡'
    case "bull":     result.first = '•'
    case "hellip":   result.first = '…'
    case "permil":   result.first = '‰'
    case "prime":    result.first = '′'
    case "Prime":    result.first = '″'
    case "lsaquo":   result.first = '‹'
    case "rsaquo":   result.first = '›'
    case "oline":    result.first = '‾'
    case "frasl":    result.first = '⁄'
    case "euro":     result.first = '€'
    case "trade":    result.first = '™'
    case "larr":     result.first = '←'
    case "uarr":     result.first = '↑'
    case "rarr":     result.first = '→'
    case "darr":     result.first = '↓'
    case "harr":     result.first = '↔'
    case "crarr":    result.first = '↵'
    case "lArr":     result.first = '⇐'
    case "uArr":     result.first = '⇑'
    case "rArr":     result.first = '⇒'
    case "dArr":     result.first = '⇓'
    case "hArr":     result.first = '⇔'
    case "forall":   result.first = '∀'
    case "part":     result.first = '∂'
    case "exist":    result.first = '∃'
    case "empty":    result.first = '∅'
    case "nabla":    result.first = '∇'
    case "isin":     result.first = '∈'
    case "notin":    result.first = '∉'
    case "ni":       result.first = '∋'
    case "prod":     result.first = '∏'
    case "sum":      result.first = '∑'
    case "minus":    result.first = '−'
    case "lowast":   result.first = '∗'
    case "radic":    result.first = '√'
    case "prop":     result.first = '∝'
    case "infin":    result.first = '∞'
    case "ang":      result.first = '∠'
    case "and":      result.first = '∧'
    case "or":       result.first = '∨'
    case "cap":      result.first = '∩'
    case "cup":      result.first = '∪'
    case "int":      result.first = '∫'
    case "there4":   result.first = '∴'
    case "sim":      result.first = '∼'
    case "cong":     result.first = '≅'
    case "asymp":    result.first = '≈'
    case "ne":       result.first = '≠'
    case "equiv":    result.first = '≡'
    case "le":       result.first = '≤'
    case "ge":       result.first = '≥'
    case "sub":      result.first = '⊂'
    case "sup":      result.first = '⊃'
    case "nsub":     result.first = '⊄'
    case "sube":     result.first = '⊆'
    case "supe":     result.first = '⊇'
    case "oplus":    result.first = '⊕'
    case "otimes":   result.first = '⊗'
    case "perp":     result.first = '⊥'
    case "sdot":     result.first = '⋅'
    case "lceil":    result.first = '⌈'
    case "rceil":    result.first = '⌉'
    case "lfloor":   result.first = '⌊'
    case "rfloor":   result.first = '⌋'
    case "lang":     result.first = '〈'
    case "rang":     result.first = '〉'
    case "loz":      result.first = '◊'
    case "spades":   result.first = '♠'
    case "clubs":    result.first = '♣'
    case "hearts":   result.first = '♥'
    case "diams":    result.first = '♦'
    case "Alpha":    result.first = 'Α'
    case "Beta":     result.first = 'Β'
    case "Gamma":    result.first = 'Γ'
    case "Delta":    result.first = 'Δ'
    case "Epsilon":  result.first = 'Ε'
    case "Zeta":     result.first = 'Ζ'
    case "Eta":      result.first = 'Η'
    case "Theta":    result.first = 'Θ'
    case "Iota":     result.first = 'Ι'
    case "Kappa":    result.first = 'Κ'
    case "Lambda":   result.first = 'Λ'
    case "Mu":       result.first = 'Μ'
    case "Nu":       result.first = 'Ν'
    case "Xi":       result.first = 'Ξ'
    case "Omicron":  result.first = 'Ο'
    case "Pi":       result.first = 'Π'
    case "Rho":      result.first = 'Ρ'
    case "Sigma":    result.first = 'Σ'
    case "Tau":      result.first = 'Τ'
    case "Upsilon":  result.first = 'Υ'
    case "Phi":      result.first = 'Φ'
    case "Chi":      result.first = 'Χ'
    case "Psi":      result.first = 'Ψ'
    case "Omega":    result.first = 'Ω'
    case "alpha":    result.first = 'α'
    case "beta":     result.first = 'β'
    case "gamma":    result.first = 'γ'
    case "delta":    result.first = 'δ'
    case "epsilon":  result.first = 'ε'
    case "zeta":     result.first = 'ζ'
    case "eta":      result.first = 'η'
    case "theta":    result.first = 'θ'
    case "iota":     result.first = 'ι'
    case "kappa":    result.first = 'κ'
    case "lambda":   result.first = 'λ'
    case "mu":       result.first = 'μ'
    case "nu":       result.first = 'ν'
    case "xi":       result.first = 'ξ'
    case "omicron":  result.first = 'ο'
    case "pi":       result.first = 'π'
    case "rho":      result.first = 'ρ'
    case "sigmaf":   result.first = 'ς'
    case "sigma":    result.first = 'σ'
    case "tau":      result.first = 'τ'
    case "upsilon":  result.first = 'υ'
    case "phi":      result.first = 'φ'
    case "chi":      result.first = 'χ'
    case "psi":      result.first = 'ψ'
    case "omega":    result.first = 'ω'
    case "thetasym": result.first = 'ϑ'
    case "upsih":    result.first = 'ϒ'
    case "piv":      result.first = 'ϖ'
    case "check":    result.first = '✓'
    case "cross":    result.first = '✗'
    case "star":     result.first = '☆'
    case "starf":    result.first = '★'
    }

    return result
}

// Windows-1252 replacements the HTML parsing specification mandates for the C1 numeric range,
// because authoring tools emitted those byte values for typographic punctuation.
private func htmlNumericReplacement(value: u64)->rune
{
    switch value
    {
    case 0x80: return '€'
    case 0x82: return '‚'
    case 0x83: return 'ƒ'
    case 0x84: return '„'
    case 0x85: return '…'
    case 0x86: return '†'
    case 0x87: return '‡'
    case 0x88: return 'ˆ'
    case 0x89: return '‰'
    case 0x8A: return 'Š'
    case 0x8B: return '‹'
    case 0x8C: return 'Œ'
    case 0x8E: return 'Ž'
    case 0x91: return '‘'
    case 0x92: return '’'
    case 0x93: return '“'
    case 0x94: return '”'
    case 0x95: return '•'
    case 0x96: return '–'
    case 0x97: return '—'
    case 0x98: return '˜'
    case 0x99: return '™'
    case 0x9A: return 'š'
    case 0x9B: return '›'
    case 0x9C: return 'œ'
    case 0x9E: return 'ž'
    case 0x9F: return 'Ÿ'
    }

    return cast(rune) value
}

// Decodes the character reference starting at `start`, which must address an `&`.
//
// A reference that cannot be resolved reports `eat == 0`, and the caller keeps the `&` as text.
// The longest complete reference wins, so `&notin;` decodes as `∉` rather than as `¬` followed
// by `in;`.
func htmlDecodeEntity(source: string, start: u64)->HtmlEntity
{
    var result: retval
    if start >= @countof(source) or source[start] != '&' do
        return result

    // A reference name never runs past this many bytes, so a stray `&` in prose costs a bounded
    // scan instead of a search to the end of the document.
    const MaxEntityLength = 32'u64

    let limit = Math.min(start + MaxEntityLength, @countof(source))
    var close = start + 1
    while close < limit and source[close] != ';' do
        close += 1
    if close >= limit or close == start + 1 do
        return result

    let name = source[start + 1 until close]
    if name[0] == '#'
    {
        if @countof(name) < 2 do
            return result
        let hexadecimal = name[1] == 'x' or name[1] == 'X'
        let digits      = hexadecimal ? name[2 to] : name[1 to]
        if !@countof(digits) do
            return result

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

        let character = htmlNumericReplacement(number)
        if !Utf8.isValidRune(character) or !number do
            return result
        result.first = character
        result.eat   = close - start + 1
        return result
    }

    result     = htmlNamedEntity(name)
    result.eat = result.first ? close - start + 1 : 0
    return result
}

// Expands every character reference of `source` into a decoded copy.
func htmlDecodeText(source: string)->String
{
    var result: retval
    var index  = 0'u64
    var copied = 0'u64
    while index < @countof(source)
    {
        if source[index] != '&'
        {
            index += 1
            continue
        }

        let entity = htmlDecodeEntity(source, index)
        if !entity.eat
        {
            index += 1
            continue
        }

        result += source[copied until index]
        result.append(entity.first)
        if entity.second do
            result.append(entity.second)
        index  += entity.eat
        copied = index
    }

    if !copied do
        return String.from(source)
    result += source[copied to]
    return result
}
