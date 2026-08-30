#global internal

using Core, Pixel

// How a CSS length produces a used value.
//
// Absolute units are folded to pixels while the style is computed, because the font size they
// depend on is already known there. Percentages, viewport units and flexible tracks stay symbolic
// until layout knows the box they apply to.
// A zero length is what a box has when nothing says otherwise — a margin, a padding and a gap
// are all zero by default — so `Pixels` is the kind an unset length carries.
#[Swag.NoDoc]
public enum HtmlLengthKind
{
    Pixels
    Auto
    Percent
    ViewportWidth
    ViewportHeight
    Fraction
    MinContent
    MaxContent
    FitContent
    Calc
    None
}

// One CSS length, kept small enough to store a full property set per element.
#[Swag.NoDoc]
public struct HtmlLength
{
    kind:  HtmlLengthKind
    value: f32
}

// The operation one node of a parsed `calc()` expression performs.
#[Swag.NoDoc]
public enum HtmlCalcOp
{
    Value
    Add
    Sub
    Mul
    Div
    Min
    Max
    Clamp
}

// One node of a parsed math expression.
//
// A `Value` node carries the coefficients of every unit that cannot be folded early, so
// `calc(100% - 44px)` is one node and needs no tree at all.
#[Swag.NoDoc]
public struct HtmlCalcNode
{
    op:      HtmlCalcOp
    pixels:  f32
    percent: f32
    vw:      f32
    vh:      f32
    left  = HtmlNoNode
    right = HtmlNoNode
    extra = HtmlNoNode
}

// What a length needs from its surroundings to produce a pixel value.
#[Swag.NoDoc]
public struct HtmlLengthContext
{
    fontSize:       f32 = 16
    rootFontSize:   f32 = 16
    viewportWidth:  f32
    viewportHeight: f32
    basis:          f32
    hasBasis:       bool
}

// Everything a computed style points into instead of storing inline.
//
// Math expressions and the few strings a style carries live here so [[HtmlComputedStyle]] stays a
// flat value that can be copied per element without a heap allocation.
#[Swag.NoDoc]
public struct HtmlValuePool
{
    calc:    Array'HtmlCalcNode
    strings: Array'String
}

impl HtmlValuePool
{
    mtd clear()
    {
        .calc.clear()
        .strings.clear()
    }

    mtd addCalc(node: HtmlCalcNode)->u32
    {
        let index = cast(u32) .calc.count
        .calc.add(node)
        return index
    }

    mtd addString(value: string)->u32
    {
        for index in .strings.count where .strings[index].toString() == value do
            return cast(u32) index
        let index = cast(u32) .strings.count
        .strings.add(String.from(value))
        return index
    }

    mtd const text(index: u32)->string
    {
        if index >= .strings.count do
            return ""
        return .strings[index].toString()
    }

    // Evaluates one math node against the surroundings a box provides.
    mtd const evaluateCalc(index: u32, context: HtmlLengthContext)->f32
    {
        if index >= .calc.count do
            return 0

        let node = &.calc[index]
        switch node.op
        {
        case .Value:
            var result = node.pixels
            result += node.percent * (context.hasBasis ? context.basis : 0)
            result += node.vw * context.viewportWidth
            result += node.vh * context.viewportHeight
            return result

        case .Add:
            return .evaluateCalc(node.left, context) + .evaluateCalc(node.right, context)

        case .Sub:
            return .evaluateCalc(node.left, context) - .evaluateCalc(node.right, context)

        case .Mul:
            return .evaluateCalc(node.left, context) * .evaluateCalc(node.right, context)

        case .Div:
            let divisor = .evaluateCalc(node.right, context)
            return divisor == 0 ? 0 : .evaluateCalc(node.left, context) / divisor

        case .Min:
            return Math.min(.evaluateCalc(node.left, context), .evaluateCalc(node.right, context))

        case .Max:
            return Math.max(.evaluateCalc(node.left, context), .evaluateCalc(node.right, context))

        case .Clamp:
            let low   = .evaluateCalc(node.left, context)
            let value = .evaluateCalc(node.right, context)
            let high  = .evaluateCalc(node.extra, context)
            return Math.clamp(value, low, high)
        }

        return 0
    }

    // Reports whether one math expression needs the containing block as a percentage basis.
    // Viewport units are definite on their own: `calc(100vh - 64px)` remains usable even when
    // the parent has an automatic height.
    mtd const calcNeedsBasis(index: u32)->bool
    {
        if index >= .calc.count do
            return false

        let node = &.calc[index]
        if node.op == .Value do
            return node.percent != 0

        if .calcNeedsBasis(node.left) or .calcNeedsBasis(node.right) do
            return true
        return node.op == .Clamp and .calcNeedsBasis(node.extra)
    }
}

impl HtmlLength
{
    // Creates the CSS `auto` length.
    #[ConstExpr]
    public func auto()->HtmlLength => {.Auto, 0}

    func pixels(value: f32)->HtmlLength => {.Pixels, value}

    func percent(value: f32)->HtmlLength => {.Percent, value}

    mtd const isAuto()->bool => .kind == .Auto

    mtd const isNone()->bool => .kind == .None

    // Reports whether the length needs the content to be measured before it can be used.
    mtd const isIntrinsic()->bool => .kind == .MinContent or .kind == .MaxContent or .kind == .FitContent

    // Returns the used pixel value, or `fallback` when the length has no definite answer.
    mtd const resolve(pool: const *HtmlValuePool, context: HtmlLengthContext, fallback = 0.0'f32)->f32
    {
        switch .kind
        {
        case .Pixels:         return .value
        case .Percent:        return context.hasBasis ? .value * context.basis : fallback
        case .ViewportWidth:  return .value * context.viewportWidth
        case .ViewportHeight: return .value * context.viewportHeight
        case .Calc:           return pool.evaluateCalc(cast(u32) .value, context)
        }

        return fallback
    }

    // Reports whether the length produces a pixel value without measuring anything.
    mtd const isDefinite(pool: const *HtmlValuePool, hasBasis: bool)->bool
    {
        switch .kind
        {
        case .Pixels, .ViewportWidth, .ViewportHeight: return true
        case .Percent: return hasBasis
        case .Calc:    return hasBasis or !pool.calcNeedsBasis(cast(u32) .value)
        }

        return false
    }
}

// Splits a declaration value into its top-level components, keeping a function call whole.
func htmlSplitValue(value: string, separator: u8 = ' ')->Array'String
{
    var result: retval
    var depth = 0'u32
    var start = 0'u64
    var index = 0'u64
    var quote = 0'u8

    while index < value.count
    {
        let character = value[index]
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
        }

        let split = !depth and (character == separator or (separator == ' ' and Latin1.isSpace(character)))
        if split
        {
            let part = Latin1.trim(value[start until index])
            if part.count do
                result.add(String.from(part))
            start = index + 1
        }

        index += 1
    }

    if index > start
    {
        let last = Latin1.trim(value[start until index])
        if last.count do
            result.add(String.from(last))
    }

    return result
}

// Returns the argument list of `name(...)`, or an empty array when the text is another value.
func htmlFunctionArguments(value: string, name: string)->{ arguments: Array'String, matched: bool }
{
    var result: retval
    if value.count <= name.count + 1 do
        return result
    if Utf8.compare(value[0 until name.count], name, .Latin1NoCase) != 0 do
        return result
    if value[name.count] != '(' or value[value.count - 1] != ')' do
        return result

    result.matched   = true
    result.arguments = htmlSplitValue(value[name.count + 1 until value.count - 1], ','u8)
    return result
}

// Reads a leading decimal number.
//
// CSS has no exponent notation, so the numeric prefix is delimited here rather than handed whole
// to a general float reader: `2em` is the number two followed by a unit, and a reader that
// accepts exponents would take `2e` for the start of one and answer something else.
func htmlParseNumber(text: string)->{ value: f32, eat: u64 }
{
    var result: retval
    var index  = 0'u64
    var digits = 0'u64

    if index < text.count and (text[index] == '+' or text[index] == '-') do
        index += 1
    while index < text.count and Latin1.isDigit(text[index])
    {
        index  += 1
        digits += 1
    }

    if index < text.count and text[index] == '.'
    {
        index += 1
        while index < text.count and Latin1.isDigit(text[index])
        {
            index  += 1
            digits += 1
        }
    }

    if !digits do
        return result

    let parsed = catch StrConv.parseF64(text[0 until index]) as parseError
    if parseError != null or parsed.ovf do
        return result

    result.value = cast(f32) parsed.value
    result.eat   = index
    return result
}

// Converts an absolute CSS unit to pixels, given the font sizes it may refer to.
private func htmlAbsoluteUnit(value: f32, unit: string, context: HtmlLengthContext)->{ pixels: f32, matched: bool }
{
    var result: retval
    result.matched = true
    switch unit
    {
    case "", "px": result.pixels = value
    case "em":     result.pixels = value * context.fontSize
    case "rem":    result.pixels = value * context.rootFontSize
    case "ex":     result.pixels = value * context.fontSize * 0.5
    case "ch":     result.pixels = value * context.fontSize * 0.5
    case "pt":     result.pixels = value * 96 / 72
    case "pc":     result.pixels = value * 16
    case "in":     result.pixels = value * 96
    case "cm":     result.pixels = value * 96 / 2.54
    case "mm":     result.pixels = value * 96 / 25.4
    case "q":      result.pixels = value * 96 / 101.6
    default:       result.matched = false
    }

    return result
}

// Parses one length component into a math node, so a `calc()` operand and a plain length share
// the same reading.
private func htmlParseCalcTerm(text: string, context: HtmlLengthContext)->{ node: HtmlCalcNode, matched: bool }
{
    var result: retval
    let trimmed = Latin1.trim(text)
    let number  = htmlParseNumber(trimmed)
    if !number.eat do
        return result

    let unit = String.from(Latin1.trim(trimmed[number.eat to])).toLower()
    switch unit.toString()
    {
    case "%":
        result.node.percent = number.value / 100
        result.matched      = true

    case "vw", "vmin":
        result.node.vw = number.value / 100
        result.matched = true

    case "vh", "vmax":
        result.node.vh = number.value / 100
        result.matched = true

    default:
        let absolute = htmlAbsoluteUnit(number.value, unit.toString(), context)
        result.node.pixels = absolute.pixels
        result.matched     = absolute.matched
    }

    return result
}

// Parses a math expression into the pool, returning the index of its root node.
//
// The grammar is the CSS one: `+` and `-` at the lowest precedence, then `*` and `/`, then
// parentheses and the `min`, `max` and `clamp` functions.
private func htmlParseCalcExpression(pool: *HtmlValuePool, text: string, context: HtmlLengthContext)->u32
{
    var scan = 0'u64
    let root = htmlParseCalcSum(pool, text, &scan, context)
    return root
}

private func htmlSkipCalcSpace(text: string, scan: *u64)
{
    while scan[] < text.count and Latin1.isSpace(text[scan[]]) do
        scan[] += 1
}

private func htmlParseCalcSum(pool: *HtmlValuePool, text: string, scan: *u64, context: HtmlLengthContext)->u32
{
    var left = htmlParseCalcProduct(pool, text, scan, context)
    while left != HtmlNoNode
    {
        htmlSkipCalcSpace(text, scan)
        if scan[] >= text.count do
            break
        let operator = text[scan[]]
        if operator != '+' and operator != '-' do
            break

        scan[] += 1
        let right = htmlParseCalcProduct(pool, text, scan, context)
        if right == HtmlNoNode do
            break

        var node: HtmlCalcNode
        node.op    = operator == '+' ? .Add : .Sub
        node.left  = left
        node.right = right
        left       = pool.addCalc(node)
    }

    return left
}

private func htmlParseCalcProduct(pool: *HtmlValuePool, text: string, scan: *u64, context: HtmlLengthContext)->u32
{
    var left = htmlParseCalcPrimary(pool, text, scan, context)
    while left != HtmlNoNode
    {
        htmlSkipCalcSpace(text, scan)
        if scan[] >= text.count do
            break
        let operator = text[scan[]]
        if operator != '*' and operator != '/' do
            break

        scan[] += 1
        let right = htmlParseCalcPrimary(pool, text, scan, context)
        if right == HtmlNoNode do
            break

        var node: HtmlCalcNode
        node.op    = operator == '*' ? .Mul : .Div
        node.left  = left
        node.right = right
        left       = pool.addCalc(node)
    }

    return left
}

// Reads the balanced text of a call whose opening parenthesis `scan` addresses.
func htmlReadBalanced(text: string, scan: *u64)->string
{
    let start = scan[] + 1
    var depth = 1'u32
    var index = start
    while index < text.count and depth
    {
        if text[index] == '(' do
            depth += 1
        elif text[index] == ')' do
            depth -= 1
        if depth do
            index += 1
    }

    scan[] = Math.min(index + 1, text.count)
    return text[start until Math.min(index, text.count)]
}

private func htmlParseCalcPrimary(pool: *HtmlValuePool, text: string, scan: *u64, context: HtmlLengthContext)->u32
{
    htmlSkipCalcSpace(text, scan)
    if scan[] >= text.count do
        return HtmlNoNode

    if text[scan[]] == '('
    {
        let inner = htmlReadBalanced(text, scan)
        return htmlParseCalcExpression(pool, inner, context)
    }

    let nameStart = scan[]
    var nameEnd   = scan[]
    while nameEnd < text.count and (Latin1.isLetter(text[nameEnd]) or text[nameEnd] == '-') do
        nameEnd += 1

    if nameEnd > nameStart and nameEnd < text.count and text[nameEnd] == '('
    {
        let name = String.from(text[nameStart until nameEnd]).toLower()
        scan[] = nameEnd
        let inner     = htmlReadBalanced(text, scan)
        let arguments = htmlSplitValue(inner, ','u8)
        switch name.toString()
        {
        case "calc":
            return htmlParseCalcExpression(pool, inner, context)

        case "min", "max":
            return htmlFoldCalcArguments(pool, arguments.toSlice(), name == "min" ? HtmlCalcOp.Min : HtmlCalcOp.Max, context)

        case "clamp":
            if arguments.count != 3 do
                return HtmlNoNode
            var node: HtmlCalcNode
            node.op    = .Clamp
            node.left  = htmlParseCalcExpression(pool, arguments[0].toString(), context)
            node.right = htmlParseCalcExpression(pool, arguments[1].toString(), context)
            node.extra = htmlParseCalcExpression(pool, arguments[2].toString(), context)
            if node.left == HtmlNoNode or node.right == HtmlNoNode or node.extra == HtmlNoNode do
                return HtmlNoNode
            return pool.addCalc(node)
        }

        return HtmlNoNode
    }

    var termEnd = scan[]
    while termEnd < text.count and text[termEnd] != '+' and text[termEnd] != '-' and text[termEnd] != '*' and text[termEnd] != '/' and text[termEnd] != ')' do
        termEnd += 1

    // A sign belongs to the number when nothing readable precedes it.
    if termEnd == scan[] and (text[termEnd] == '+' or text[termEnd] == '-')
    {
        termEnd += 1
        while termEnd < text.count and text[termEnd] != '+' and text[termEnd] != '-' and text[termEnd] != '*' and text[termEnd] != '/' and text[termEnd] != ')' do
            termEnd += 1
    }

    let term = htmlParseCalcTerm(text[scan[] until termEnd], context)
    scan[] = termEnd
    if !term.matched do
        return HtmlNoNode
    return pool.addCalc(term.node)
}

private func htmlFoldCalcArguments(pool: *HtmlValuePool, arguments: const [..] String, op: HtmlCalcOp, context: HtmlLengthContext)->u32
{
    if !arguments.count do
        return HtmlNoNode

    var folded = htmlParseCalcExpression(pool, arguments[0].toString(), context)
    for index in 1 until arguments.count
    {
        let right = htmlParseCalcExpression(pool, arguments[index].toString(), context)
        if folded == HtmlNoNode or right == HtmlNoNode do
            return HtmlNoNode

        var node: HtmlCalcNode
        node.op    = op
        node.left  = folded
        node.right = right
        folded     = pool.addCalc(node)
    }

    return folded
}

// Parses a length, a percentage, a keyword size, or a math expression.
func htmlParseLength(pool: *HtmlValuePool, text: string, context: HtmlLengthContext)->{ length: HtmlLength, matched: bool }
{
    var result: retval
    let trimmed = Latin1.trim(text)
    if !trimmed.count do
        return result

    let lower = String.from(trimmed).toLower()
    switch lower.toString()
    {
    case "auto":
        result.length.kind = .Auto
        result.matched     = true
        return result

    case "none":
        result.length.kind = .None
        result.matched     = true
        return result

    case "min-content":
        result.length.kind = .MinContent
        result.matched     = true
        return result

    case "max-content":
        result.length.kind = .MaxContent
        result.matched     = true
        return result

    case "fit-content":
        result.length.kind = .FitContent
        result.matched     = true
        return result

    case "inherit", "initial", "unset", "revert":
        return result
    }

    let number = htmlParseNumber(lower.toString())
    if number.eat
    {
        let unit = Latin1.trim(lower.toString()[number.eat to])
        if !unit.count or unit == "px"
        {
            result.length  = HtmlLength.pixels(number.value)
            result.matched = true
            return result
        }

        switch unit
        {
        case "%":
            result.length  = HtmlLength.percent(number.value / 100)
            result.matched = true
            return result

        case "fr":
            result.length.kind  = .Fraction
            result.length.value = number.value
            result.matched      = true
            return result

        case "vw", "vmin":
            result.length.kind  = .ViewportWidth
            result.length.value = number.value / 100
            result.matched      = true
            return result

        case "vh", "vmax":
            result.length.kind  = .ViewportHeight
            result.length.value = number.value / 100
            result.matched      = true
            return result
        }

        let absolute = htmlAbsoluteUnit(number.value, unit, context)
        if absolute.matched
        {
            result.length  = HtmlLength.pixels(absolute.pixels)
            result.matched = true
        }

        return result
    }

    // Anything left is a math expression; a single node that only carries pixels is folded so a
    // trivial `calc()` costs nothing at layout.
    var scan = 0'u64
    let root = htmlParseCalcPrimary(pool, lower.toString(), &scan, context)
    if root == HtmlNoNode do
        return result

    let node = &pool.calc[root]
    if node.op == .Value and !node.percent and !node.vw and !node.vh
    {
        result.length  = HtmlLength.pixels(node.pixels)
        result.matched = true
        return result
    }

    result.length.kind  = .Calc
    result.length.value = cast(f32) root
    result.matched      = true
    return result
}
