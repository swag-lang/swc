#global internal

using Core

// How a compound selector relates to the one written before it.
#[Swag.NoDoc]
public enum HtmlCombinator
{
    Descendant
    Child
    NextSibling
    LaterSibling
}

// The comparison an attribute selector performs.
#[Swag.NoDoc]
public enum HtmlAttributeMatch
{
    Exists
    Equals
    Includes
    DashMatch
    Prefix
    Suffix
    Contains
}

// The generated box a selector addresses, when it addresses one.
#[Swag.NoDoc]
public enum HtmlPseudoElement
{
    None
    Before
    After
    Marker
    Unsupported
}

// The state-dependent and structural conditions a compound selector carries.
#[Swag.EnumFlags, Swag.NoDoc]
public enum HtmlPseudoClass
{
    None = 0
    Root
    FirstChild
    LastChild
    OnlyChild
    FirstOfType
    LastOfType
    Empty
    Target
    Checked
    Disabled
    Nth
    NthOfType
    Never
}

// One `[name op "value"]` condition.
#[Swag.NoDoc]
public struct HtmlAttributeSelector
{
    name:  String
    value: String
    match: HtmlAttributeMatch
}

// One compound selector: everything written between two combinators.
//
// `:not(...)`, `:is(...)` and `:where(...)` hold compound selectors of their own, which live in
// the sheet's shared pool so this stays a flat value.
#[Swag.NoDoc]
public struct HtmlSelectorPart
{
    tag:           String
    id:            String
    classes:       Array'String
    attributes:    Array'HtmlAttributeSelector
    pseudo = HtmlPseudoClass.None
    pseudoElement: HtmlPseudoElement

    // The `an+b` form of a structural pseudo-class, matching positions `a*k + b` for `k >= 0`.
    nthA:        s32
    nthB:        s32
    rejectFirst: u32
    rejectCount: u32
    acceptFirst: u32
    acceptCount: u32
    combinator:  HtmlCombinator
}

// One declaration, kept as text until an element needs its computed value.
//
// A declaration is parsed once and matched many times, so its value only becomes a length or a
// color for the elements that actually select it.
#[Swag.NoDoc]
public struct HtmlDeclaration
{
    property:  HtmlProperty
    name:      String
    value:     String
    important: bool
}

// The declarations one `{ ... }` block holds, shared by every selector of its group.
#[Swag.NoDoc]
public struct HtmlDeclarationBlock
{
    declarations: Array'HtmlDeclaration
}

// One selector with the block it applies.
#[Swag.NoDoc]
public struct HtmlRule
{
    parts:       Array'HtmlSelectorPart
    block:       u32
    media = HtmlNoNode
    specificity: u32
    order:       u32
}

// What the surroundings answer when a media query asks.
#[Swag.NoDoc]
public struct HtmlMediaState
{
    viewportWidth:  f32
    viewportHeight: f32
    darkScheme:     bool
}

// A parsed collection of CSS rules, indexed for matching.
//
// Rules are bucketed by the id, classes and tag of their subject, so an element only compares
// itself against the rules that can possibly apply to it. A sheet with a thousand rules then
// costs a handful of comparisons per element instead of a thousand.
#[Swag.NoDoc]
public struct HtmlStyleSheet
{
    blocks:     Array'HtmlDeclarationBlock
    rules:      Array'HtmlRule
    subParts:   Array'HtmlSelectorPart
    media:      Array'String
    idIndex:    HashTable'(String, Array'u32)
    classIndex: HashTable'(String, Array'u32)
    tagIndex:   HashTable'(String, Array'u32)
    universal:  Array'u32
    order:      u32
}

// The document state a selector can ask about.
#[Swag.NoDoc]
public struct HtmlMatchContext
{
    #[Swag.Late]
    document: *HtmlDocument

    target:  String
    mediaOn: Array'bool

    elementIndex:    Array'u32
    elementCount:    Array'u32
    typeIndex:       Array'u32
    typeCount:       Array'u32
    previousElement: Array'u32
    numElements:     u64
}

impl HtmlMatchContext
{
    // Records sibling relationships once so structural pseudo-classes do not repeatedly scan a
    // large parent's children. Stored previous-element indices are offset by one, leaving zero as
    // the sentinel for nodes without a previous element.
    mtd prepare(document: *HtmlDocument)
    {
        .document = document
        .elementIndex.clear()
        .elementCount.clear()
        .typeIndex.clear()
        .typeCount.clear()
        .previousElement.clear()
        .numElements = 0
        .elementIndex.resize(document.nodes.count)
        .elementCount.resize(document.nodes.count)
        .typeIndex.resize(document.nodes.count)
        .typeCount.resize(document.nodes.count)
        .previousElement.resize(document.nodes.count)

        var totals:  HashTable'(String, u32)
        var indices: HashTable'(String, u32)
        for parentIndex in document.nodes.count
        {
            let children = document.constNode(cast(u32) parentIndex).children
            if children.isEmpty() do
                continue

            totals.clear()
            var count    = 0'u32
            var previous = HtmlNoNode
            for child in children
            {
                let node = document.constNode(child)
                if node.kind != .Element do
                    continue

                count                   += 1
                .numElements            += 1
                .elementIndex[child]    = count
                .previousElement[child] = previous == HtmlNoNode ? 0 : previous + 1
                previous                = child
                totals.findOrAdd(document.name(child)).value += 1
            }

            indices.clear()
            for child in children
            {
                let node = document.constNode(child)
                if node.kind != .Element do
                    continue

                .elementCount[child] = count
                let name  = document.name(child)
                let index = indices.findOrAdd(name)
                index.value       += 1
                .typeIndex[child] = index.value
                .typeCount[child] = totals.tryFind(name)!.value
            }
        }
    }

    mtd const elementPosition(element: u32)->{ index: u32, count: u32 }
    {
        if element >= @countof(.elementIndex) or !.elementIndex[element] do
            return {1, 1}
        return {.elementIndex[element], .elementCount[element]}
    }

    mtd const typePosition(element: u32)->{ index: u32, count: u32 }
    {
        if element >= @countof(.typeIndex) or !.typeIndex[element] do
            return {1, 1}
        return {.typeIndex[element], .typeCount[element]}
    }

    mtd const previous(element: u32)->u32
    {
        if element >= @countof(.previousElement) or !.previousElement[element] do
            return HtmlNoNode
        return .previousElement[element] - 1
    }
}

impl HtmlSelectorPart
{
    // Adds the weight this compound selector contributes, in the usual three CSS categories.
    mtd const addSpecificity(specificity: *u32)
    {
        if !.id.isEmpty() do
            specificity[] += 1 << 20
        specificity[] += cast(u32) .classes.count << 10
        specificity[] += cast(u32) .attributes.count << 10
        if .pseudo != .None do
            specificity[] += 1 << 10
        if !.tag.isEmpty() do
            specificity[] += 1
        if .pseudoElement != .None do
            specificity[] += 1
    }
}

impl HtmlStyleSheet
{
    mtd clear()
    {
        .blocks.clear()
        .rules.clear()
        .subParts.clear()
        .media.clear()
        .idIndex.clear()
        .classIndex.clear()
        .tagIndex.clear()
        .universal.clear()
        .order = 0
    }

    // Registers a rule under the most selective key its subject offers.
    private mtd indexRule(index: u32)
    {
        let subject = .rules[index].parts.backPtr()
        if !subject.id.isEmpty()
        {
            .idIndex.findOrAdd(subject.id).value.add(index)
            return
        }

        if subject.classes.count
        {
            .classIndex.findOrAdd(subject.classes[0]).value.add(index)
            return
        }

        if !subject.tag.isEmpty()
        {
            .tagIndex.findOrAdd(subject.tag).value.add(index)
            return
        }

        .universal.add(index)
    }

    // Collects every rule that can apply to an element, in source order.
    mtd const candidates(document: const *HtmlDocument, element: u32, output: *Array'u32)
    {
        output.clear()
        let id = document.id(element)
        if @countof(id)
        {
            let found = .idIndex.tryFind(id)
            if found do
                output.add(found!.value.toSlice())
        }

        for value in document.classes(element)
        {
            let found = .classIndex.tryFind(document.text(value[]))
            if found do
                output.add(found!.value.toSlice())
        }

        let byTag = .tagIndex.tryFind(document.name(element))
        if byTag do
            output.add(byTag!.value.toSlice())
        output.add(.universal.toSlice())
        output.sort()
    }

    // Reports whether one compound selector describes an element.
    mtd const matchesPart(part: const *HtmlSelectorPart, element: u32, context: const *HtmlMatchContext)->bool
    {
        let document = context.document
        let node     = document.constNode(element)
        if node.kind != .Element do
            return false
        if !part.tag.isEmpty() and part.tag != document.name(element) do
            return false
        if !part.id.isEmpty() and part.id != document.id(element) do
            return false

        for value in part.classes where !document.hasClass(element, value.toString()) do
            return false

        for attribute in part.attributes where !.matchesAttribute(attribute, element, document) do
            return false

        if part.pseudo != .None and !.matchesPseudo(part, element, context) do
            return false

        for index in part.rejectCount where .matchesPart(&.subParts[part.rejectFirst + index], element, context) do
            return false

        if part.acceptCount
        {
            var accepted: bool
            for index in part.acceptCount where .matchesPart(&.subParts[part.acceptFirst + index], element, context)
            {
                accepted = true
                break
            }

            if !accepted do
                return false
        }

        return true
    }

    private mtd const matchesAttribute(attribute: const *HtmlAttributeSelector, element: u32, document: const *HtmlDocument)->bool
    {
        if !document.hasAttribute(element, attribute.name.toString()) do
            return false

        let value    = document.attribute(element, attribute.name.toString())
        let expected = attribute.value.toString()
        switch attribute.match
        {
        case .Exists:
            return true

        case .Equals:
            return value == expected

        case .Includes:
            for part in Tokenize.split(value, ' 'u8) where part == expected do
                return true
            return false

        case .DashMatch:
            return value == expected or (Utf8.startsWith(value, expected) and @countof(value) > @countof(expected) and value[@countof(expected)] == '-')

        case .Prefix:
            return @countof(expected) and Utf8.startsWith(value, expected)

        case .Suffix:
            return @countof(expected) and Utf8.endsWith(value, expected)

        case .Contains:
            return @countof(expected) and Utf8.contains(value, expected)
        }

        return false
    }

    private mtd const matchesPseudo(part: const *HtmlSelectorPart, element: u32, context: const *HtmlMatchContext)->bool
    {
        let document = context.document
        let pseudo   = part.pseudo
        if pseudo.has(.Never) do
            return false
        if pseudo.has(.Root) and document.constNode(element).parent != 0 do
            return false

        if pseudo.has(.Target) and (context.target.isEmpty() or document.id(element) != context.target.toString()) do
            return false
        if pseudo.has(.Checked) and !document.hasAttribute(element, "checked") do
            return false
        if pseudo.has(.Disabled) and !document.hasAttribute(element, "disabled") do
            return false
        if pseudo.has(.Empty) and document.constNode(element).children.count do
            return false

        let structural = HtmlPseudoClass.FirstChild | .LastChild | .OnlyChild | .FirstOfType | .LastOfType | .Nth | .NthOfType
        if (pseudo & structural) == .None do
            return true

        let position = context.elementPosition(element)
        if pseudo.has(.FirstChild) and position.index != 1 do
            return false
        if pseudo.has(.LastChild) and position.index != position.count do
            return false
        if pseudo.has(.OnlyChild) and position.count != 1 do
            return false
        if pseudo.has(.Nth) and !HtmlStyleSheet.matchesNthForm(part.nthA, part.nthB, position.index) do
            return false

        if pseudo.has(.FirstOfType) or pseudo.has(.LastOfType) or pseudo.has(.NthOfType)
        {
            let ofType = context.typePosition(element)
            if pseudo.has(.FirstOfType) and ofType.index != 1 do
                return false
            if pseudo.has(.LastOfType) and ofType.index != ofType.count do
                return false
            if pseudo.has(.NthOfType) and !HtmlStyleSheet.matchesNthForm(part.nthA, part.nthB, ofType.index) do
                return false
        }

        return true
    }

    // Reports whether a position satisfies an `a*k + b` form for some non-negative integer `k`.
    private func matchesNthForm(a, b: s32, index: u32)->bool
    {
        let position = cast(s32) index
        if a == 0 do
            return position == b

        let delta = position - b
        if a > 0 do
            return delta >= 0 and delta % a == 0
        return delta <= 0 and delta % a == 0
    }

    // Reports whether a whole selector chain describes an element.
    //
    // The chain is matched from its subject backwards, because that is the direction in which a
    // failing compound selector rejects the rule immediately.
    mtd const matches(rule: const *HtmlRule, element: u32, context: const *HtmlMatchContext)->bool
    {
        if rule.media != HtmlNoNode and (rule.media >= @countof(context.mediaOn) or !context.mediaOn[rule.media]) do
            return false
        if !.matchesPart(&rule.parts[rule.parts.count - 1], element, context) do
            return false
        if rule.parts.count == 1 do
            return true

        return .matchesAncestors(rule, cast(u32) rule.parts.count - 1, element, context)
    }

    private mtd const matchesAncestors(rule: const *HtmlRule, partIndex: u32, element: u32, context: const *HtmlMatchContext)->bool
    {
        if !partIndex do
            return true

        let document = context.document
        let part     = &rule.parts[partIndex]
        let previous = &rule.parts[partIndex - 1]
        switch part.combinator
        {
        case .Child:
            let parent = document.constNode(element).parent
            if parent == HtmlNoNode or !.matchesPart(previous, parent, context) do
                return false
            return .matchesAncestors(rule, partIndex - 1, parent, context)

        case .Descendant:
            var walk = document.constNode(element).parent
            while walk != HtmlNoNode
            {
                if .matchesPart(previous, walk, context) and .matchesAncestors(rule, partIndex - 1, walk, context) do
                    return true
                walk = document.constNode(walk).parent
            }

            return false

        case .NextSibling:
            let sibling = context.previous(element)
            if sibling == HtmlNoNode or !.matchesPart(previous, sibling, context) do
                return false
            return .matchesAncestors(rule, partIndex - 1, sibling, context)

        case .LaterSibling:
            var sibling = context.previous(element)
            while sibling != HtmlNoNode
            {
                if .matchesPart(previous, sibling, context) and .matchesAncestors(rule, partIndex - 1, sibling, context) do
                    return true
                sibling = context.previous(sibling)
            }

            return false
        }

        return false
    }

    // Answers every media query the sheet carries, in rule-index order.
    mtd const evaluateMedia(state: HtmlMediaState)->Array'bool
    {
        var result: retval
        for query in .media do
            result.add(HtmlStyleSheet.evaluateMediaQuery(query.toString(), state))
        return result
    }

    private func evaluateMediaQuery(query: string, state: HtmlMediaState)->bool
    {
        for alternative in Tokenize.split(query, ','u8) where HtmlStyleSheet.evaluateMediaAlternative(Latin1.trim(alternative), state) do
            return true
        return false
    }

    private func evaluateMediaAlternative(query: string, state: HtmlMediaState)->bool
    {
        var negated: bool
        var text = Latin1.trim(query)
        if Utf8.startsWith(text, "not ")
        {
            negated = true
            text    = Latin1.trim(text[4 to])
        }
        elif Utf8.startsWith(text, "only ")
        {
            text = Latin1.trim(text[5 to])
        }

        var matched = true
        var index   = 0'u64
        while index < @countof(text)
        {
            while index < @countof(text) and Latin1.isSpace(text[index]) do
                index += 1
            if index >= @countof(text) do
                break

            if text[index] == '('
            {
                var scan  = index
                let inner = htmlReadBalanced(text, &scan)
                if !HtmlStyleSheet.evaluateMediaFeature(inner, state) do
                    matched = false
                index = scan
                continue
            }

            var wordEnd = index
            while wordEnd < @countof(text) and !Latin1.isSpace(text[wordEnd]) and text[wordEnd] != '(' do
                wordEnd += 1

            // The only media types a document window can answer for are the screen ones.
            let word = String.from(text[index until wordEnd]).toLower()
            if word == "print" or word == "speech" do
                matched = false
            index = wordEnd
        }

        return negated ? !matched : matched
    }

    private func evaluateMediaFeature(feature: string, state: HtmlMediaState)->bool
    {
        let colon = Utf8.indexOf(feature, ':'rune)
        let name  = String.from(Latin1.trim(colon == Swag.U64.Max ? feature : feature[0 until colon])).toLower()
        let value = String.from(Latin1.trim(colon == Swag.U64.Max ? "" : feature[colon + 1 to])).toLower()

        var context: HtmlLengthContext
        context.viewportWidth  = state.viewportWidth
        context.viewportHeight = state.viewportHeight

        var pool: HtmlValuePool
        let length = htmlParseLength(&pool, value.toString(), context)
        let pixels = length.matched ? length.length.resolve(&pool, context) : 0

        switch name.toString()
        {
        case "prefers-color-scheme":   return value == (state.darkScheme ? "dark" : "light")
        case "min-width":              return state.viewportWidth >= pixels
        case "max-width":              return state.viewportWidth <= pixels
        case "min-height":             return state.viewportHeight >= pixels
        case "max-height":             return state.viewportHeight <= pixels
        case "width":                  return state.viewportWidth == pixels
        case "height":                 return state.viewportHeight == pixels
        case "orientation":            return value == (state.viewportWidth >= state.viewportHeight ? "landscape" : "portrait")
        case "prefers-reduced-motion": return value == "no-preference" or !value.length
        case "prefers-contrast":       return value == "no-preference" or !value.length
        }

        // A feature the engine does not model describes the host rather than the document, and a
        // desktop browser answers most of them positively.
        return true
    }
}

// Removes comments from a stylesheet, leaving the text a rule parser can scan linearly.
private func htmlStripCssComments(source: string)->String
{
    var result: retval
    var index  = 0'u64
    var quote  = 0'u8
    var copied = 0'u64

    while index < @countof(source)
    {
        let character = source[index]
        if quote
        {
            if character == '\\' do
                index += 1
            elif character == quote do
                quote = 0
            index += 1
            continue
        }

        if character == '"' or character == '\''
        {
            quote = character
            index += 1
            continue
        }

        if character == '/' and index + 1 < @countof(source) and source[index + 1] == '*'
        {
            result += source[copied until index]
            let end = Utf8.indexOf(source, "*/", index + 2)
            index  = end == Swag.U64.Max ? @countof(source) : end + 2
            copied = index
            continue
        }

        index += 1
    }

    if !copied do
        return String.from(source)
    result += source[copied to]
    return result
}

impl HtmlStyleSheet
{
    // Appends every rule of a stylesheet text.
    mtd parse(source: string)
    {
        let stripped = htmlStripCssComments(source)
        .parseRules(stripped.toString(), HtmlNoNode)
    }

    private mtd parseRules(source: string, media: u32)
    {
        var index = 0'u64
        while index < @countof(source)
        {
            while index < @countof(source) and Latin1.isSpace(source[index]) do
                index += 1
            if index >= @countof(source) do
                return

            if source[index] == '@'
            {
                index = .parseAtRule(source, index, media)
                continue
            }

            let brace = HtmlStyleSheet.findBlockStart(source, index)
            if brace == Swag.U64.Max do
                return

            var scan = brace
            let body = htmlReadBalancedBrace(source, &scan)
            .addRules(source[index until brace], body, media)
            index = scan
        }
    }

    // Finds the `{` that opens a rule body, ignoring the ones inside quotes and parentheses.
    private func findBlockStart(source: string, from: u64)->u64
    {
        var index = from
        var depth = 0'u32
        var quote = 0'u8
        while index < @countof(source)
        {
            let character = source[index]
            if quote
            {
                if character == quote do
                    quote = 0
                index += 1
                continue
            }

            switch character
            {
            case '"', '\'':
                quote = character

            case '(':
                depth += 1

            case ')':
                if depth do
                    depth -= 1

            case '{':
                if !depth do
                    return index

            case ';', '}':
                if !depth do
                    return Swag.U64.Max
            }

            index += 1
        }

        return Swag.U64.Max
    }

    private mtd parseAtRule(source: string, from: u64, media: u32)->u64
    {
        var nameEnd = from + 1
        while nameEnd < @countof(source) and (Latin1.isLetter(source[nameEnd]) or source[nameEnd] == '-') do
            nameEnd += 1

        let name      = String.from(source[from + 1 until nameEnd]).toLower()
        let brace     = HtmlStyleSheet.findBlockStart(source, nameEnd)
        let semicolon = Utf8.indexOf(source, ';'rune, nameEnd)
        if brace == Swag.U64.Max
        {
            return semicolon == Swag.U64.Max ? @countof(source) : semicolon + 1
        }

        var scan = brace
        let body = htmlReadBalancedBrace(source, &scan)
        switch name.toString()
        {
        case "media":
            let query = Latin1.trim(source[nameEnd until brace])
            let index = cast(u32) .media.count
            .media.add(String.from(query))
            .parseRules(body, index)

        case "supports", "layer", "scope", "container":
            .parseRules(body, media)
        }

        return scan
    }

    // Parses one `selectors { declarations }` rule into as many rules as it lists selectors.
    private mtd addRules(prelude: string, body: string, media: u32)
    {
        let declarations = HtmlStyleSheet.parseDeclarations(body)
        if declarations.declarations.isEmpty() do
            return

        let block     = cast(u32) .blocks.count
        let selectors = htmlSplitValue(prelude, ','u8)
        var added: bool
        for selector in selectors
        {
            var rule = .parseSelector(selector.toString())
            if rule.parts.isEmpty() do
                continue

            let subject = rule.parts.backPtr()
            if subject.pseudoElement == .Unsupported do
                continue

            rule.block = block
            rule.media = media
            rule.order = .order
            .order     += 1
            for &part in rule.parts do
                part.addSpecificity(&rule.specificity)

            let index = cast(u32) .rules.count
            .rules.add(#move rule)
            .indexRule(index)
            added = true
        }

        if added do
            .blocks.add(#move declarations)
    }

    // Splits a declaration body into its `name: value` pairs.
    func parseDeclarations(body: string)->HtmlDeclarationBlock
    {
        var result: retval
        let statements = htmlSplitValue(body, ';'u8)
        for statement in statements
        {
            let text  = statement.toString()
            let colon = Utf8.indexOf(text, ':'rune)
            if colon == Swag.U64.Max do
                continue

            let property = Latin1.trim(text[0 until colon])
            var value    = Latin1.trim(text[colon + 1 to])
            if !@countof(property) or !@countof(value) do
                continue

            var declaration: HtmlDeclaration
            let bang = Utf8.indexOf(value, '!'rune)
            if bang != Swag.U64.Max and Utf8.compare(Latin1.trim(value[bang + 1 to]), "important", .Latin1NoCase) == 0
            {
                declaration.important = true
                value                 = Latin1.trim(value[0 until bang])
            }

            // A custom property keeps the author's case, because it is a name and not a keyword.
            if Utf8.startsWith(property, "--")
            {
                declaration.property = .Custom
                declaration.name     = property
            }
            else
            {
                let lower = String.from(property).toLower()
                declaration.property = htmlPropertyFromName(lower.toString())
                if declaration.property == .Unknown do
                    continue
                declaration.name = #move lower
            }

            declaration.value = value
            result.declarations.add(#move declaration)
        }

        return result
    }

    // Parses one complete selector chain.
    private mtd parseSelector(selector: string)->HtmlRule
    {
        var result: retval
        var index = 0'u64

        // Whitespace only separates compound selectors; the descendant relation is what stands
        // when no explicit combinator was written between two of them.
        var combinator = HtmlCombinator.Descendant

        while index < @countof(selector)
        {
            let character = selector[index]
            if Latin1.isSpace(character)
            {
                index += 1
                continue
            }

            switch character
            {
            case '>':
                combinator = .Child
                index      += 1
                continue

            case '+':
                combinator = .NextSibling
                index      += 1
                continue

            case '~':
                combinator = .LaterSibling
                index      += 1
                continue
            }

            let compound = .parseCompound(selector, &index)
            if !compound.matched
            {
                result.parts.clear()
                return result
            }

            var part = compound.part
            part.combinator = combinator
            result.parts.add(#move part)
            combinator = .Descendant
        }

        return result
    }

    // Parses everything a compound selector holds, stopping at the next combinator.
    private mtd parseCompound(selector: string, index: *u64)->{ part: HtmlSelectorPart, matched: bool }
    {
        var result: retval
        var read:   bool

        while index[] < @countof(selector)
        {
            let character = selector[index[]]
            if Latin1.isSpace(character) or character == '>' or character == '+' or character == '~' do
                break

            switch character
            {
            case '*':
                index[] += 1
                read    = true

            case '#':
                index[]        += 1
                result.part.id = HtmlStyleSheet.readIdentifier(selector, index)
                read           = true

            case '.':
                index[] += 1
                result.part.classes.add(HtmlStyleSheet.readIdentifier(selector, index))
                read = true

            case '[':
                if !.readAttributeSelector(&result.part, selector, index) do
                    return result
                read = true

            case ':':
                if !.readPseudo(&result.part, selector, index) do
                    return result
                read = true

            default:
                if !Latin1.isLetterOrDigit(character) and character != '-' and character != '_' do
                    return result
                var name = HtmlStyleSheet.readIdentifier(selector, index)
                result.part.tag = name.toLower()
                read            = true
            }
        }

        result.matched = read
        return result
    }

    private func readIdentifier(selector: string, index: *u64)->String
    {
        var result: retval
        let start = index[]
        while index[] < @countof(selector)
        {
            let character = selector[index[]]
            if !Latin1.isLetterOrDigit(character) and character != '-' and character != '_' and character != '\\' do
                break
            index[] += 1
        }

        result = selector[start until index[]]
        return result
    }

    private mtd readAttributeSelector(part: *HtmlSelectorPart, selector: string, index: *u64)->bool
    {
        let close = Utf8.indexOf(selector, ']'rune, index[])
        if close == Swag.U64.Max do
            return false

        let body = Latin1.trim(selector[index[] + 1 until close])
        index[] = close + 1

        var attribute: HtmlAttributeSelector
        var nameEnd = 0'u64
        while nameEnd < @countof(body) and (Latin1.isLetterOrDigit(body[nameEnd]) or body[nameEnd] == '-' or body[nameEnd] == '_') do
            nameEnd += 1
        if !nameEnd do
            return false

        attribute.name = String.from(body[0 until nameEnd]).toLower()
        var rest = Latin1.trim(body[nameEnd to])
        if !@countof(rest)
        {
            part.attributes.add(#move attribute)
            return true
        }

        var valueStart = 1'u64
        switch rest[0]
        {
        case '=': attribute.match = .Equals
        case '~': attribute.match = .Includes
        case '|': attribute.match = .DashMatch
        case '^': attribute.match = .Prefix
        case '$': attribute.match = .Suffix
        case '*': attribute.match = .Contains
        default:  return false
        }

        if attribute.match != .Equals
        {
            if @countof(rest) < 2 or rest[1] != '=' do
                return false
            valueStart = 2
        }

        var value = Latin1.trim(rest[valueStart to])

        // A case-insensitivity flag is accepted and ignored, because a document that carries one
        // still selects the same element in practice.
        if @countof(value) >= 2 and (Utf8.endsWith(value, " i") or Utf8.endsWith(value, " I")) do
            value = Latin1.trim(value[0 until @countof(value) - 2])
        if @countof(value) >= 2 and (value[0] == '"' or value[0] == '\'') and value[@countof(value) - 1] == value[0] do
            value = value[1 until @countof(value) - 1]

        attribute.value = value
        part.attributes.add(#move attribute)
        return true
    }

    private mtd readPseudo(part: *HtmlSelectorPart, selector: string, index: *u64)->bool
    {
        index[] += 1
        var element = false
        if index[] < @countof(selector) and selector[index[]] == ':'
        {
            element = true
            index[] += 1
        }

        let name = HtmlStyleSheet.readIdentifier(selector, index).toLower()
        var argument: String
        if index[] < @countof(selector) and selector[index[]] == '('
        {
            var scan = index[]
            argument = htmlReadBalanced(selector, &scan)
            index[]  = scan
        }

        if element
        {
            switch name.toString()
            {
            case "before": part.pseudoElement = .Before
            case "after":  part.pseudoElement = .After
            case "marker": part.pseudoElement = .Marker
            default:       part.pseudoElement = .Unsupported
            }

            return true
        }

        // A vendor-prefixed pseudo-class describes a host widget this engine does not build.
        if Utf8.startsWith(name.toString(), "-")
        {
            part.pseudo.add(.Never)
            return true
        }

        switch name.toString()
        {
        case "root":
            part.pseudo.add(.Root)

        case "first-child":
            part.pseudo.add(.FirstChild)

        case "last-child":
            part.pseudo.add(.LastChild)

        case "only-child":
            part.pseudo.add(.OnlyChild)

        case "first-of-type":
            part.pseudo.add(.FirstOfType)

        case "last-of-type":
            part.pseudo.add(.LastOfType)

        case "empty":
            part.pseudo.add(.Empty)

        case "target":
            part.pseudo.add(.Target)

        case "checked":
            part.pseudo.add(.Checked)

        case "disabled":
            part.pseudo.add(.Disabled)

        // A pointer or keyboard state would have to restyle the document on every mouse move to
        // be honoured, and a document of twenty thousand elements cannot pay that per frame. The
        // viewer answers the pointer where it costs nothing instead: it lights the link under it
        // while painting, and it changes the cursor.
        case "hover", "focus", "focus-visible", "focus-within", "active":
            part.pseudo.add(.Never)

        case "before":
            part.pseudoElement = .Before

        case "after":
            part.pseudoElement = .After

        case "not":
            let first = cast(u32) .subParts.count
            if !.addSubSelectors(argument.toString()) do
                return false
            part.rejectFirst = first
            part.rejectCount = cast(u32) .subParts.count - first

        case "is", "where", "matches", "any":
            let first = cast(u32) .subParts.count
            if !.addSubSelectors(argument.toString()) do
                return false
            part.acceptFirst = first
            part.acceptCount = cast(u32) .subParts.count - first

        case "nth-child":
            HtmlStyleSheet.applyNth(part, argument.toString(), ofType: false)

        case "nth-of-type":
            HtmlStyleSheet.applyNth(part, argument.toString(), ofType: true)

        // A condition the engine cannot decide is refused rather than granted: applying a state
        // rule to every element is a worse answer than applying it to none. Everything left
        // unlisted — `:enabled`, `:link`, `:visited` and their kind — always holds here, and
        // needs no record.
        case "has", "nth-last-child", "nth-last-of-type", "only-of-type", "lang", "dir",
             "placeholder-shown", "indeterminate", "required", "optional", "invalid", "valid",
             "in-range", "out-of-range", "autofill", "modal", "popover-open", "user-invalid",
             "open", "fullscreen", "picture-in-picture":
            part.pseudo.add(.Never)
        }

        return true
    }

    // Reads the compound selectors of a functional pseudo-class into the shared pool.
    private mtd addSubSelectors(argument: string)->bool
    {
        var added: bool
        let alternatives = htmlSplitValue(argument, ','u8)
        for alternative in alternatives
        {
            var scan     = 0'u64
            let compound = .parseCompound(alternative.toString(), &scan)
            if !compound.matched do
                continue
            var part = compound.part
            .subParts.add(#move part)
            added = true
        }

        return added
    }

    // Parses the full `an+b` grammar: `odd`, `even`, a bare index, `3n`, `2n+1`, `-n+3`, with or
    // without spaces around the sign. A form that does not parse matches nothing, which is what
    // an invalid selector argument means.
    private func applyNth(part: *HtmlSelectorPart, argument: string, ofType: bool)
    {
        var compact: String
        for character in Latin1.trim(argument) where !Latin1.isSpace(character) do
            compact.append(Latin1.toLower(character))

        var a, b:    s32
        var matched: bool
        switch compact.toString()
        {
        case "odd":
            a       = 2
            b       = 1
            matched = true

        case "even":
            a       = 2
            matched = true

        default:
            let text = compact.toString()
            let n    = Utf8.indexOf(text, 'n'rune)
            if n == Swag.U64.Max
            {
                let number = htmlParseNumber(text)
                if number.eat == @countof(text)
                {
                    b       = cast(s32) number.value
                    matched = true
                }
            }
            else
            {
                let aPart = text[0 until n]
                matched = true
                if !@countof(aPart) or aPart == "+" do
                    a = 1
                elif aPart == "-" do
                    a = -1
                else
                {
                    let number = htmlParseNumber(aPart)
                    if number.eat == @countof(aPart) do
                        a = cast(s32) number.value
                    else do
                        matched = false
                }

                let bPart = text[n + 1 to]
                if @countof(bPart) and matched
                {
                    let number = htmlParseNumber(bPart)
                    if number.eat == @countof(bPart) do
                        b = cast(s32) number.value
                    else do
                        matched = false
                }
            }
        }

        if !matched
        {
            part.pseudo.add(.Never)
            return
        }

        part.nthA = a
        part.nthB = b
        part.pseudo.add(ofType ? HtmlPseudoClass.NthOfType : HtmlPseudoClass.Nth)
    }
}

// Reads the text of a `{ ... }` body whose opening brace `scan` addresses, leaving `scan` after
// the closing one.
private func htmlReadBalancedBrace(source: string, scan: *u64)->string
{
    let start = scan[] + 1
    var depth = 1'u32
    var index = start
    var quote = 0'u8

    while index < @countof(source) and depth
    {
        let character = source[index]
        if quote
        {
            if character == quote do
                quote = 0
            index += 1
            continue
        }

        switch character
        {
        case '"', '\'': quote = character
        case '{':       depth += 1
        case '}':       depth -= 1
        }

        if depth do
            index += 1
    }

    scan[] = Math.min(index + 1, @countof(source))
    return source[start until Math.min(index, @countof(source))]
}
