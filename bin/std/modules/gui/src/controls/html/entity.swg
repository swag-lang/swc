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

// Resolves a complete name through the packed table. The exact name bytes distinguish hash collisions.
private func htmlNamedEntity(name: string)->HtmlEntity
{
    var slot = htmlNamedRefSlot(name)
    while true
    {
        let index = HtmlPackedNamedRefs.slots[slot]
        if not index
        {
            return {}
        }

        let entry = &HtmlPackedNamedRefs.entries[index - 1]
        if entry.length == name.count and
           not Swag.memcmp(&HtmlPackedNamedRefs.names[entry.offset], name.buffer, name.count)
        {
            return {first: entry.first, second: entry.second}
        }

        slot = (slot + 1) & (HtmlNamedRefSlotCount - 1)
    }
}

// Returns the index of `name` in a table sorted by name, or `Swag.U64.Max`.
private func htmlFindNamedRef(table: const [..] HtmlNamedRef, name: string)->u64
{
    var low  = 0_u64
    var high = table.count
    while low < high
    {
        let middle = low + (high - low) / 2
        let order  = Latin1.compare(table[middle].name, name)
        if not order
        {
            return middle
        }

        if order < 0
        {
            low = middle + 1
        }
        else
        {
            high = middle
        }
    }

    return Swag.U64.Max
}

// Returns the longest legacy reference the text spells without its semicolon, and how many bytes
// it occupies after the `&`.
//
// The standard keeps these for the documents that wrote them, and refuses them inside an
// attribute value when a name or an `=` follows: `?a=1&copy=2` is a query string, not a mark.
private func htmlLegacyEntity(text: string, inAttribute: bool)->HtmlEntity
{
    var result: #returntype
    var length = Math.min(text.count, HtmlMaxLegacyRefName)
    while length >= 2
    {
        let found = htmlFindNamedRef(HtmlLegacyRefs, text[0 until length])
        if found != Swag.U64.Max
        {
            if inAttribute and length < text.count
            {
                let next = text[length]
                if next == '=' or Latin1.isLetterOrDigit(next)
                {
                    return result
                }
            }

            result.first  = HtmlLegacyRefs[found].first
            result.second = HtmlLegacyRefs[found].second
            result.eat    = length
            return result
        }

        length -= 1
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

    return cast(rune, value)
}

// Decodes the character reference starting at `start`, which must address an `&`.
//
// A reference that cannot be resolved reports `eat == 0`, and the caller keeps the `&` as text.
// The longest complete reference wins, so `&notin;` decodes as `∉` rather than as `¬` followed
// by `in;`.
func htmlDecodeEntity(source: string, start: u64, inAttribute = false)->HtmlEntity
{
    var result: #returntype
    if start >= source.count or source[start] != '&'
    {
        return result
    }

    // A reference never runs past the longest name the standard lists, plus its `&` and its `;`,
    // so a stray `&` in prose costs a bounded scan instead of a search to the end of the document.
    let limit = Math.min(start + HtmlMaxRefName + 2, source.count)
    var close = start + 1
    while close < limit and source[close] != ';'
    {
        close += 1
    }

    if close >= limit or close == start + 1
    {
        return htmlDecodeLegacyEntity(source, start, inAttribute)
    }

    let name = source[start + 1 until close]
    if name[0] == '#'
    {
        if name.count < 2
        {
            return result
        }

        let hexadecimal = name[1] == 'x' or name[1] == 'X'
        let digits      = hexadecimal ? name[2 to] : name[1 to]
        if not digits.count
        {
            return result
        }

        var number: u64
        if hexadecimal
        {
            var parseErrorOutcome: Swag.Error
            var parsed: #decltype(expect StrConv.parseX64(digits))
            catch { parsed = try StrConv.parseX64(digits) } as parseErrorOutcome
            let parseError = parseErrorOutcome.value()
            if parseError != null or parsed.ovf or parsed.eat != digits.count
            {
                return result
            }

            number = parsed.value
        }
        else
        {
            var parseErrorOutcome: Swag.Error
            var parsed: #decltype(expect StrConv.parseU64(digits))
            catch { parsed = try StrConv.parseU64(digits) } as parseErrorOutcome
            let parseError = parseErrorOutcome.value()
            if parseError != null or parsed.ovf or parsed.eat != digits.count
            {
                return result
            }

            number = parsed.value
        }

        let character = htmlNumericReplacement(number)
        if not Utf8.isValidRune(character) or not number
        {
            return result
        }

        result.first = character
        result.eat   = close - start + 1
        return result
    }

    result = htmlNamedEntity(name)
    if not result.first
    {
        return htmlDecodeLegacyEntity(source, start, inAttribute)
    }

    result.eat = close - start + 1
    return result
}

// Resolves the reference a document spells without its semicolon, which the standard still lists.
private func htmlDecodeLegacyEntity(source: string, start: u64, inAttribute: bool)->HtmlEntity
{
    var result: #returntype
    let tail   = source[start + 1 until Math.min(start + 1 + HtmlMaxRefName, source.count)]
    let legacy = htmlLegacyEntity(tail, inAttribute)
    if not legacy.eat
    {
        return result
    }

    result     = legacy
    result.eat += 1
    return result
}

// Expands every character reference of `source` into a decoded copy.
func htmlDecodeText(source: string)->String
{
    var result: #returntype
    htmlDecodeInto(&result, source)
    return result
}

// Appends source text to `output`, resolving the character references it carries.
//
// Most text carries none, and the scan for the next `&` is the vectorized one, so the common run
// is appended in a single copy.
func htmlDecodeInto(output: *String, source: string, inAttribute = false)
{
    var index  = 0_u64
    var copied = 0_u64
    while index < source.count
    {
        let next = Utf8.indexOf(source, '&'_rune, index)
        if next == Swag.U64.Max
        {
            break
        }

        let entity = htmlDecodeEntity(source, next, inAttribute)
        if not entity.eat
        {
            index = next + 1
            continue
        }

        output[] += source[copied until next]
        output.append(entity.first)
        if entity.second
        {
            output.append(entity.second)
        }

        index  = next + entity.eat
        copied = index
    }

    output[] += source[copied to]
}
