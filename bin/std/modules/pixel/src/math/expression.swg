#global public

using Core
using Errors

// Selects sizing and limit placement for a mathematical expression.
//
// Display style puts limits above and below large operators, while text style keeps
// them beside the operator. Script styles are selected automatically for nested
// subscripts, superscripts, fractions, and matrix cells.
enum MathStyle
{
    Display          // Full-size stand-alone formula with limits above and below large operators.
    Text             // Inline formula with compact operator limits.
    Script           // First-level subscript or superscript style.
    ScriptScript     // Nested subscript or superscript style.
}

// Reports the extent of a laid-out mathematical expression.
//
// The baseline is `ascent` pixels below the top.
struct MathMetrics
{
    public
    {
        width:   f32     // Horizontal extent in pixels.
        ascent:  f32     // Distance from the baseline to the top edge, in pixels.
        descent: f32     // Distance from the baseline to the bottom edge, in pixels.
    }
}

impl MathMetrics
{
    // Returns the total vertical extent, `ascent + descent`, in pixels.
    mtd const height()->f32 => .ascent + .descent
}

// Configures mathematical expression layout.
//
// Values expressed in em scale with the supplied font. The defaults follow the
// proportions used by modern TeX/OpenType math engines and remain useful with an
// ordinary text font that has no OpenType MATH table.
struct MathLayoutOptions
{
    public
    {
        style:             MathStyle = Display     // Root style used to begin layout.
        scriptScale:       f32       = 0.72        // Font-size multiplier for first-level scripts.
        scriptScriptScale: f32       = 0.55        // Font-size multiplier for nested scripts.
        ruleThicknessEm:   f32       = 0.055       // Fraction and radical rule thickness in em.
        minRuleThickness:  f32       = 1.0         // Minimum visible rule thickness in pixels.
        rowGapEm:          f32       = 0.32        // Vertical gap between matrix rows in em.
        columnGapEm:       f32       = 0.65        // Horizontal gap between matrix columns in em.
    }
}

internal enum MathNodeKind
{
    Row
    Symbol
    Space
    Fraction
    Radical
    Scripts
    Delimited
    Accent
    Matrix
    Style
}

internal enum MathAtomClass
{
    Ord
    Op
    Bin
    Rel
    Open
    Close
    Punct
    Inner
}

internal enum MathFontVariant
{
    Default
    Roman
    Italic
    Bold
    BoldItalic
}

internal enum MathLimitsMode
{
    Automatic
    Limits
    NoLimits
}

#[Swag.EnumFlags]
private enum MathParseStop
{
    None
    Brace
    Bracket
    Right
    Matrix
}

internal struct MathRule
{
    start: Math.Vector2
    end:   Math.Vector2
    width: f32
}

internal struct MathDrawText
{
    text:  string
    pos:   Math.Vector2     // Baseline-relative position
    font:  *Font
    scale: f32
}

internal enum MathPathKind
{
    Radical
    LeftParenthesis
    RightParenthesis
    LeftBracket
    RightBracket
    LeftBrace
    RightBrace
    LeftAngle
    RightAngle
    LeftFloor
    RightFloor
    LeftCeiling
    RightCeiling
    Bar
    DoubleBar
    Hat
    Tilde
    Vector
}

internal struct MathDrawPath
{
    kind:      MathPathKind
    rect:      Math.Rectangle     // Baseline-relative bounds
    lineWidth: f32
    aux:       f32     // Kind-specific local coordinate
}

internal struct MathNode
{
    id:        u64
    kind:      MathNodeKind
    atomClass: MathAtomClass = Ord
    text:      String
    text2:     String
    children:  Array'(*MathNode)

    metrics: MathMetrics
    offsets: Array'Math.Vector2
    rules:   Array'MathRule
    draws:   Array'MathDrawText
    paths:   Array'MathDrawPath

    style:       MathStyle
    fontVariant: MathFontVariant = Default
    limitsMode:  MathLimitsMode  = Automatic
    spaceEm:     f32
    flag:        bool
    flag2:       bool
    rowLengths:  Array'u32
}

// Stores a parsed, reusable mathematical expression.
//
// The accepted input is a practical LaTeX math subset; no surrounding `$`
// delimiters are needed. It includes:
// - grouped rows, Unicode literals, sub/superscripts and TeX atom spacing;
// - fractions, binomials, indexed roots, scalable delimiters and common accents;
// - Greek letters, relations, arrows, named functions and large operators/limits;
// - roman/italic/bold/text runs and explicit TeX spacing;
// - matrix, pmatrix, bmatrix, Bmatrix, vmatrix, Vmatrix, cases and aligned.
//
// Parse expressions once when they are drawn repeatedly:
//
// ## Example
//
// ```swag
// var expression = try Pixel.MathExpression.parse(#raw "\frac{x_i^2}{\sqrt{1+x}}")
// let metrics = painter.drawMath(20, 30, &expression, font, Pixel.Argb.MidnightBlue)
// ```
#[Swag.Opaque]
struct MathExpression
{
    // The parsed expression tree. Build it with 'parse' and render it with the layout pass;
    // the node pool owns every node, so a caller holding one would outlive its storage.
    // The module reads the tree directly to check the parser.

    internal
    {
        source:    String                // Expression text the tree was parsed from.
        nodes:     ArrayPtr'MathNode     // Pool owning every node of the tree.
        late root: *MathNode             // Root of the tree, set by 'parse'.
    }
}

private struct MathSymbolSpec
{
    text:          string
    atomClass:     MathAtomClass
    found:         bool
    largeOperator: bool
    limitsMode:    MathLimitsMode = Automatic
}

private struct MathParser
{
    expression: *MathExpression
    source:     string
    pos:        u64
}

private func mathFail(message: string, seek: u64) fail
{
    fail SyntaxError{Errors.mkString(Format.toString("% at byte %", message, seek)), seek: seek}
}

private func mathOwnedSlice(source: string, start, end: u64)->String
{
    var result: retval
    if end > start do
        result = Swag.makeString(source.buffer + start, end - start)
    return result
}

private func mathIsAsciiLetter(c: u8)->bool => c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z'

internal func mathStyleScale(style: MathStyle, options: MathLayoutOptions)->f32
{
    switch style
    {
    case .Script:       return options.scriptScale
    case .ScriptScript: return options.scriptScriptScale
    }

    return 1.0
}

internal func mathNextStyle(style: MathStyle)->MathStyle
{
    switch style
    {
    case .Display: return .Script
    case .Text:    return .Script
    }

    return .ScriptScript
}

internal func mathCrampedStyle(style: MathStyle)->MathStyle
{
    if style == .Display do
        return .Text
    return mathNextStyle(style)
}

private func mathLiteralClass(c: rune)->MathAtomClass
{
    switch c
    {
    case '+', '-', '*', '/', '\u00D7'rune, '\u00F7'rune: return .Bin
    case '=', '<', '>', '\u2260'rune, '\u2264'rune, '\u2265'rune: return .Rel
    case '(', '[', '{': return .Open
    case ')', ']', '}': return .Close
    case ',', ';', ':': return .Punct
    case '|': return .Rel
    }

    return .Ord
}

private func mathIsAsciiVariable(text: string)->bool
{
    if text.count != 1 do
        return false
    return mathIsAsciiLetter(text.buffer[0])
}

private func mathSymbol(text: string,
                        atomClass = MathAtomClass.Ord,
                        large = false,
                        limitsMode = MathLimitsMode.Automatic)->MathSymbolSpec
{
    with var result: retval
    {
        .text          = text
        .atomClass     = atomClass
        .found         = true
        .largeOperator = large
        .limitsMode    = limitsMode
    }

    return result
}

// Common LaTeX math commands. Unicode is the interchange layer between the
// parser and Pixel's font renderer, so a font can provide its best matching glyph.
private func mathCommandSymbol(command: string)->MathSymbolSpec
{
    switch command
    {
    // Greek lowercase
    case "alpha":      return mathSymbol("\u03B1")
    case "beta":       return mathSymbol("\u03B2")
    case "gamma":      return mathSymbol("\u03B3")
    case "delta":      return mathSymbol("\u03B4")
    case "epsilon":    return mathSymbol("\u03F5")
    case "varepsilon": return mathSymbol("\u03B5")
    case "zeta":       return mathSymbol("\u03B6")
    case "eta":        return mathSymbol("\u03B7")
    case "theta":      return mathSymbol("\u03B8")
    case "vartheta":   return mathSymbol("\u03D1")
    case "iota":       return mathSymbol("\u03B9")
    case "kappa":      return mathSymbol("\u03BA")
    case "lambda":     return mathSymbol("\u03BB")
    case "mu":         return mathSymbol("\u03BC")
    case "nu":         return mathSymbol("\u03BD")
    case "xi":         return mathSymbol("\u03BE")
    case "pi":         return mathSymbol("\u03C0")
    case "varpi":      return mathSymbol("\u03D6")
    case "rho":        return mathSymbol("\u03C1")
    case "varrho":     return mathSymbol("\u03F1")
    case "sigma":      return mathSymbol("\u03C3")
    case "varsigma":   return mathSymbol("\u03C2")
    case "tau":        return mathSymbol("\u03C4")
    case "upsilon":    return mathSymbol("\u03C5")
    case "phi":        return mathSymbol("\u03D5")
    case "varphi":     return mathSymbol("\u03C6")
    case "chi":        return mathSymbol("\u03C7")
    case "psi":        return mathSymbol("\u03C8")
    case "omega":      return mathSymbol("\u03C9")

    // Greek uppercase
    case "Gamma":   return mathSymbol("\u0393")
    case "Delta":   return mathSymbol("\u0394")
    case "Theta":   return mathSymbol("\u0398")
    case "Lambda":  return mathSymbol("\u039B")
    case "Xi":      return mathSymbol("\u039E")
    case "Pi":      return mathSymbol("\u03A0")
    case "Sigma":   return mathSymbol("\u03A3")
    case "Upsilon": return mathSymbol("\u03A5")
    case "Phi":     return mathSymbol("\u03A6")
    case "Psi":     return mathSymbol("\u03A8")
    case "Omega":   return mathSymbol("\u03A9")

    // Binary operators
    case "pm":            return mathSymbol("\u00B1", .Bin)
    case "mp":            return mathSymbol("\u2213", .Bin)
    case "times":         return mathSymbol("\u00D7", .Bin)
    case "div":           return mathSymbol("\u00F7", .Bin)
    case "cdot":          return mathSymbol("\u22C5", .Bin)
    case "ast":           return mathSymbol("\u2217", .Bin)
    case "star":          return mathSymbol("\u22C6", .Bin)
    case "circ":          return mathSymbol("\u2218", .Bin)
    case "bullet":        return mathSymbol("\u2219", .Bin)
    case "cap":           return mathSymbol("\u2229", .Bin)
    case "cup":           return mathSymbol("\u222A", .Bin)
    case "setminus":      return mathSymbol("\u2216", .Bin)
    case "land", "wedge": return mathSymbol("\u2227", .Bin)
    case "lor", "vee":    return mathSymbol("\u2228", .Bin)
    case "oplus":         return mathSymbol("\u2295", .Bin)
    case "ominus":        return mathSymbol("\u2296", .Bin)
    case "otimes":        return mathSymbol("\u2297", .Bin)
    case "oslash":        return mathSymbol("\u2298", .Bin)

    // Relations
    case "le", "leq": return mathSymbol("\u2264", .Rel)
    case "ge", "geq": return mathSymbol("\u2265", .Rel)
    case "ne", "neq": return mathSymbol("\u2260", .Rel)
    case "approx":    return mathSymbol("\u2248", .Rel)
    case "sim":       return mathSymbol("\u223C", .Rel)
    case "simeq":     return mathSymbol("\u2243", .Rel)
    case "equiv":     return mathSymbol("\u2261", .Rel)
    case "propto":    return mathSymbol("\u221D", .Rel)
    case "in":        return mathSymbol("\u2208", .Rel)
    case "notin":     return mathSymbol("\u2209", .Rel)
    case "ni":        return mathSymbol("\u220B", .Rel)
    case "subset":    return mathSymbol("\u2282", .Rel)
    case "supset":    return mathSymbol("\u2283", .Rel)
    case "subseteq":  return mathSymbol("\u2286", .Rel)
    case "supseteq":  return mathSymbol("\u2287", .Rel)
    case "parallel":  return mathSymbol("\u2225", .Rel)
    case "perp":      return mathSymbol("\u22A5", .Rel)
    case "mid":       return mathSymbol("\u2223", .Rel)
    case "models":    return mathSymbol("\u22A8", .Rel)

    // Arrows
    case "to", "rightarrow": return mathSymbol("\u2192", .Rel)
    case "leftarrow":        return mathSymbol("\u2190", .Rel)
    case "leftrightarrow":   return mathSymbol("\u2194", .Rel)
    case "Rightarrow":       return mathSymbol("\u21D2", .Rel)
    case "Leftarrow":        return mathSymbol("\u21D0", .Rel)
    case "Leftrightarrow":   return mathSymbol("\u21D4", .Rel)
    case "mapsto":           return mathSymbol("\u21A6", .Rel)
    case "uparrow":          return mathSymbol("\u2191", .Rel)
    case "downarrow":        return mathSymbol("\u2193", .Rel)

    // Large operators
    case "sum":      return mathSymbol("\u2211", .Op, true, .Limits)
    case "prod":     return mathSymbol("\u220F", .Op, true, .Limits)
    case "coprod":   return mathSymbol("\u2210", .Op, true, .Limits)
    case "int":      return mathSymbol("\u222B", .Op, true, .NoLimits)
    case "iint":     return mathSymbol("\u222C", .Op, true, .NoLimits)
    case "iiint":    return mathSymbol("\u222D", .Op, true, .NoLimits)
    case "oint":     return mathSymbol("\u222E", .Op, true, .NoLimits)
    case "bigcap":   return mathSymbol("\u22C2", .Op, true, .Limits)
    case "bigcup":   return mathSymbol("\u22C3", .Op, true, .Limits)
    case "bigwedge": return mathSymbol("\u22C0", .Op, true, .Limits)
    case "bigvee":   return mathSymbol("\u22C1", .Op, true, .Limits)

    // Named functions
    case "sin", "cos", "tan", "cot", "sec", "csc",
         "sinh", "cosh", "tanh", "log", "ln", "exp",
         "max", "min", "sup", "inf", "det", "gcd": return mathSymbol(command, .Op)

    case "lim", "limsup", "liminf": return mathSymbol(command, .Op, false, .Limits)

    // Delimiters and ordinary symbols
    case "lbrace":        return mathSymbol("{", .Open)
    case "rbrace":        return mathSymbol("}", .Close)
    case "langle":        return mathSymbol("\u27E8", .Open)
    case "rangle":        return mathSymbol("\u27E9", .Close)
    case "lfloor":        return mathSymbol("\u230A", .Open)
    case "rfloor":        return mathSymbol("\u230B", .Close)
    case "lceil":         return mathSymbol("\u2308", .Open)
    case "rceil":         return mathSymbol("\u2309", .Close)
    case "vert", "lvert": return mathSymbol("|", .Open)
    case "rvert":         return mathSymbol("|", .Close)
    case "Vert", "lVert": return mathSymbol("\u2016", .Open)
    case "rVert":         return mathSymbol("\u2016", .Close)
    case "infty":         return mathSymbol("\u221E")
    case "partial":       return mathSymbol("\u2202")
    case "nabla":         return mathSymbol("\u2207")
    case "forall":        return mathSymbol("\u2200")
    case "exists":        return mathSymbol("\u2203")
    case "neg", "lnot":   return mathSymbol("\u00AC")
    case "emptyset":      return mathSymbol("\u2205")
    case "ell":           return mathSymbol("\u2113")
    case "hbar":          return mathSymbol("\u210F")
    case "Re":            return mathSymbol("\u211C")
    case "Im":            return mathSymbol("\u2111")
    case "aleph":         return mathSymbol("\u2135")
    case "ldots":         return mathSymbol("\u2026", .Inner)
    case "cdots":         return mathSymbol("\u22EF", .Inner)
    default:              return {text: ""}
    }
}

private impl MathParser
{
    mtd count()->u64 => (.source).count

    mtd eof()->bool => .pos >= .count()

    mtd peek()->u8
    {
        if .eof() do
            return 0
        return (.source).buffer[.pos]
    }

    mtd peekAt(offset: u64)->u8
    {
        let at = .pos + offset
        if at >= .count() do
            return 0
        return (.source).buffer[at]
    }

    mtd skipMathSpaces()
    {
        while not .eof()
        {
            let c = .peek()
            if c != ' ' and c != '\t' and c != '\r' and c != '\n' do
                break
            .pos += 1
        }
    }

    mtd newNode(kind: MathNodeKind)->*MathNode
    {
        let node = Memory.new'MathNode()
        node.id   = .expression.nodes.count
        node.kind = kind
        .expression.nodes.add(node)
        return node
    }

    mtd newRow()->*MathNode => .newNode(.Row)

    mtd newSymbol(text: string, atomClass = MathAtomClass.Ord)->*MathNode
    {
        let node = .newNode(.Symbol)
        node.text      = text
        node.atomClass = atomClass
        return node
    }

    mtd readRune()->{ value: rune, start: u64 } fail
    {
        var result: retval
        result.start = .pos
        if .eof() do
            try mathFail("math expression ends, but this position needs an atom", .pos)

        let slice    = Swag.makeSlice((.source).buffer + .pos, .count() - .pos)
        let {c, eat} = Utf8.decodeRune(slice)
        if eat == 0 do
            try mathFail("math expression contains an incomplete UTF-8 sequence", .pos)
        result.value = c
        .pos         += eat
        return result
    }

    mtd atControlWord(word: string)->bool
    {
        if .peek() != '\\' do
            return false
        let size = word.count
        if .pos + 1 + size > .count() do
            return false
        let got = Swag.makeString((.source).buffer + .pos + 1, size)
        if got != word do
            return false
        if .pos + 1 + size < .count() and mathIsAsciiLetter((.source).buffer[.pos + 1 + size]) do
            return false
        return true
    }

    mtd readCommand()->String fail
    {
        let slash = .pos
        if .peek() != '\\' do
            try mathFail("math command needs a leading '\\'", .pos)
        .pos += 1
        if .eof() do
            try mathFail("math expression ends after '\\'", slash)

        let start = .pos
        if mathIsAsciiLetter(.peek())
        {
            while mathIsAsciiLetter(.peek()) do
                .pos += 1
        }
        else
        {
            .pos += 1
        }

        return mathOwnedSlice(.source, start, .pos)
    }

    mtd consumeControlWord(word: string)->bool fail
    {
        if not .atControlWord(word) do
            return false
        discard try .readCommand()
        .skipMathSpaces()
        return true
    }

    mtd readRawGroup(label: string)->String fail
    {
        .skipMathSpaces()
        let open = .pos
        if .peek() != '{' do
            try mathFail(Format.toString("% needs a '{...}' argument", label), .pos)
        .pos += 1

        let start = .pos
        var depth = 1'u32
        while not .eof()
        {
            let c = .peek()
            if c == '\\'
            {
                .pos += 1
                if not .eof() do
                    .pos += 1
                continue
            }

            if c == '{'
            {
                depth += 1
            }
            elif c == '}'
            {
                depth -= 1
                if depth == 0
                {
                    let result = mathOwnedSlice(.source, start, .pos)
                    .pos += 1
                    return result
                }
            }

            .pos += 1
        }

        try mathFail(Format.toString("% has no closing '}'", label), open)
        unreachable
    }

    mtd shouldStop(stop: MathParseStop)->bool
    {
        if stop & .Brace and .peek() == '}' do
            return true
        if stop & .Bracket and .peek() == ']' do
            return true
        if stop & .Right and .atControlWord("right") do
            return true
        if stop & .Matrix
        {
            if .peek() == '&' do
                return true
            if .peek() == '\\' and .peekAt(1) == '\\' do
                return true
            if .atControlWord("end") do
                return true
        }

        return false
    }

    mtd parseRow(stop = MathParseStop.None)->*MathNode fail
    {
        let row = .newRow()
        while true
        {
            .skipMathSpaces()
            if .eof() or .shouldStop(stop) do
                break

            if .peek() == '}' do
                try mathFail("math expression has a closing '}' without a matching group", .pos)
            if .peek() == ']' do
                try mathFail("math expression has a closing ']' without a matching root index", .pos)
            if .peek() == '&' do
                try mathFail("math alignment marker '&' is outside a matrix", .pos)

            row.children.add(try .parseAtom())
        }

        return row
    }

    mtd parseRequiredArgument(label: string)->*MathNode fail
    {
        .skipMathSpaces()
        if .eof() do
            try mathFail(Format.toString("% needs an argument", label), .pos)
        if .peek() == '{' do
            return try .parseGroup()

        // TeX consumes exactly one token for an unbraced argument. In `x_i^2`,
        // this keeps `^2` attached to x instead of accidentally nesting it under i.
        return try .parsePrimary()
    }

    mtd parseGroup()->*MathNode fail
    {
        let open = .pos
        if .peek() != '{' do
            try mathFail("math group needs an opening '{'", .pos)
        .pos += 1
        let result = try .parseRow(.Brace)
        if .peek() != '}' do
            try mathFail("math group has no closing '}'", open)
        .pos += 1
        return result
    }

    mtd parseBracketGroup()->*MathNode fail
    {
        let open = .pos
        if .peek() != '[' do
            try mathFail("root index needs an opening '['", .pos)
        .pos += 1
        let result = try .parseRow(.Bracket)
        if .peek() != ']' do
            try mathFail("root index has no closing ']'", open)
        .pos += 1
        return result
    }

    mtd parseDelimiter(label: string)->String fail
    {
        .skipMathSpaces()
        if .eof() do
            try mathFail(Format.toString("% needs a delimiter", label), .pos)

        if .peek() == '\\'
        {
            let at      = .pos
            let command = try .readCommand()
            let spec    = mathCommandSymbol(command)
            if not spec.found do
                try mathFail(Format.toString("% has no delimiter for command '\\%'", label, command), at)
            return spec.text
        }

        let runeInfo = try .readRune()
        return mathOwnedSlice(.source, runeInfo.start, .pos)
    }

    mtd parseLeftRight()->*MathNode fail
    {
        let left = try .parseDelimiter("'\\left'")
        let body = try .parseRow(.Right)
        if not (try .consumeControlWord("right")) do
            try mathFail("'\\left' has no matching '\\right'", .pos)
        let right = try .parseDelimiter("'\\right'")

        let node = .newNode(.Delimited)
        node.text  = left
        node.text2 = right
        node.children.add(body)
        node.atomClass = .Inner
        return node
    }

    mtd parseFraction(withRule = true)->*MathNode fail
    {
        let numerator   = try .parseRequiredArgument("fraction numerator")
        let denominator = try .parseRequiredArgument("fraction denominator")
        let node        = .newNode(.Fraction)
        node.flag = withRule
        node.children.add(numerator)
        node.children.add(denominator)
        node.atomClass = .Inner
        return node
    }

    mtd parseRadical()->*MathNode fail
    {
        .skipMathSpaces()
        var index: *MathNode?
        if .peek() == '[' do
            index = try .parseBracketGroup()
        let radicand = try .parseRequiredArgument("radical")
        let node     = .newNode(.Radical)
        node.children.add(radicand)
        if index
        {
            node.children.add(index)
            node.flag = true
        }

        node.atomClass = .Ord
        return node
    }

    mtd parseStyle(variant: MathFontVariant, label: string)->*MathNode fail
    {
        let child = try .parseRequiredArgument(label)
        let node  = .newNode(.Style)
        node.fontVariant = variant
        node.children.add(child)
        return node
    }

    mtd parseAccent(accent: string, under = false, asRule = false)->*MathNode fail
    {
        let child = try .parseRequiredArgument("math accent")
        let node  = .newNode(.Accent)
        node.text  = accent
        node.flag  = under
        node.flag2 = asRule
        node.children.add(child)
        return node
    }

    mtd parseOperatorName()->*MathNode fail
    {
        let name = try .readRawGroup("'\\operatorname'")
        return .newSymbol(name, .Op)
    }

    mtd wrapMatrix(matrix: *MathNode, environment: string)->*MathNode
    {
        var left, right: string = ""
        if environment == "pmatrix"
        {
            left  = "("
            right = ")"
        }
        elif environment == "bmatrix"
        {
            left  = "["
            right = "]"
        }
        elif environment == "Bmatrix"
        {
            left  = "{"
            right = "}"
        }
        elif environment == "vmatrix"
        {
            left  = "|"
            right = "|"
        }
        elif environment == "Vmatrix"
        {
            left  = "\u2016"
            right = "\u2016"
        }
        elif environment == "cases"
        {
            left  = "{"
            right = "."
        }
        else
        {
            return matrix
        }

        with let delimited = .newNode(.Delimited)
        {
            .text  = left
            .text2 = right
            .children.add(matrix)
            .atomClass = .Inner
        }

        return delimited
    }

    mtd parseEnvironment()->*MathNode fail
    {
        let beginAt     = .pos
        let environment = try .readRawGroup("'\\begin'")
        if environment != "matrix" and
           environment != "pmatrix" and
           environment != "bmatrix" and
           environment != "Bmatrix" and
           environment != "vmatrix" and
           environment != "Vmatrix" and
           environment != "cases" and
           environment != "aligned" do
            try mathFail(Format.toString("math renderer does not support environment '%'", environment), beginAt)

        let matrix = .newNode(.Matrix)
        matrix.atomClass = .Inner
        var columnsInRow = 0'u32

        while true
        {
            let cell = try .parseRow(.Matrix)
            matrix.children.add(cell)
            columnsInRow += 1
            .skipMathSpaces()

            if .peek() == '&'
            {
                .pos += 1
                continue
            }

            if .peek() == '\\' and .peekAt(1) == '\\'
            {
                .pos += 2
                matrix.rowLengths.add(columnsInRow)
                columnsInRow = 0
                continue
            }

            if .atControlWord("end")
            {
                discard try .readCommand()
                let closeEnvironment = try .readRawGroup("'\\end'")
                if closeEnvironment != environment do
                    try mathFail(Format.toString("'\\begin{%}' ends with '\\end{%}'", environment, closeEnvironment), .pos)
                matrix.rowLengths.add(columnsInRow)
                break
            }

            try mathFail(Format.toString("math environment '%' has no matching '\\end{%}'", environment, environment), beginAt)
        }

        return .wrapMatrix(matrix, environment)
    }

    mtd parseCommand()->*MathNode fail
    {
        let at      = .pos
        let command = try .readCommand()

        if command == "frac" or command == "dfrac" or command == "tfrac" do
            return try .parseFraction()
        if command == "binom"
        {
            let fraction = try .parseFraction(false)
            let node     = .newNode(.Delimited)
            node.text  = "("
            node.text2 = ")"
            node.children.add(fraction)
            node.atomClass = .Inner
            return node
        }

        if command == "sqrt" do
            return try .parseRadical()
        if command == "left" do
            return try .parseLeftRight()
        if command == "right" do
            try mathFail("'\\right' has no matching '\\left'", at)
        if command == "begin" do
            return try .parseEnvironment()
        if command == "end" do
            try mathFail("'\\end' has no matching '\\begin'", at)
        if command == "operatorname" do
            return try .parseOperatorName()
        if command == "text" or command == "textrm"
        {
            let text = try .readRawGroup(Format.toString("'\\%'", command))
            return .newSymbol(text)
        }

        if command == "mathrm" do
            return try .parseStyle(.Roman, "'\\mathrm'")
        if command == "mathit" do
            return try .parseStyle(.Italic, "'\\mathit'")
        if command == "mathbf" do
            return try .parseStyle(.Bold, "'\\mathbf'")
        if command == "boldsymbol" or command == "bm" do
            return try .parseStyle(.BoldItalic, Format.toString("'\\%'", command))

        if command == "hat" or command == "widehat" do
            return try .parseAccent("^")
        if command == "tilde" or command == "widetilde" do
            return try .parseAccent("~")
        if command == "bar" do
            return try .parseAccent("\u00AF")
        if command == "vec" do
            return try .parseAccent("\u2192")
        if command == "dot" do
            return try .parseAccent("\u02D9")
        if command == "ddot" do
            return try .parseAccent("\u00A8")
        if command == "overline" do
            return try .parseAccent("", false, true)
        if command == "underline" do
            return try .parseAccent("", true, true)

        let spec = mathCommandSymbol(command)
        if spec.found
        {
            let node = .newSymbol(spec.text, spec.atomClass)
            node.flag       = spec.largeOperator
            node.limitsMode = spec.limitsMode
            return node
        }

        // Explicit spacing commands
        var space = 0.0'f32
        if command == "," do
            space = 3.0 / 18.0
        elif command == ":" do
            space = 4.0 / 18.0
        elif command == ";" do
            space = 5.0 / 18.0
        elif command == "!" do
            space = -3.0 / 18.0
        elif command == " " do
            space = 1.0 / 3.0
        elif command == "quad" do
            space = 1.0
        elif command == "qquad" do
            space = 2.0
        if space != 0
        {
            let node = .newNode(.Space)
            node.spaceEm = space
            return node
        }

        // Escaped TeX punctuation is literal.
        if command == "{" do
            return .newSymbol("{", .Open)
        if command == "}" do
            return .newSymbol("}", .Close)
        if command == "_" do
            return .newSymbol("_")
        if command == "^" do
            return .newSymbol("^")
        if command == "%" do
            return .newSymbol("%")
        if command == "#" do
            return .newSymbol("#")
        if command == "&" do
            return .newSymbol("&")
        if command == "$" do
            return .newSymbol("$")
        if command == "|" do
            return .newSymbol("\u2016", .Open)
        if command == "\\" do
            try mathFail("math row break '\\\\' is outside a matrix", at)

        try mathFail(Format.toString("math renderer does not support command '\\%'", command), at)
        unreachable
    }

    mtd parsePrimary()->*MathNode fail
    {
        .skipMathSpaces()
        let at = .pos
        if .eof() do
            try mathFail("math expression ends, but this position needs an atom", at)

        if .peek() == '{' do
            return try .parseGroup()
        if .peek() == '\\' do
            return try .parseCommand()
        if .peek() == '^' or .peek() == '_' do
            try mathFail(Format.toString("math script marker '%' has no base", Swag.makeString((.source).buffer + .pos, 1)), at)
        if .peek() == '~'
        {
            .pos += 1
            let node = .newNode(.Space)
            node.spaceEm = 1.0 / 3.0
            return node
        }

        let runeInfo = try .readRune()
        let text     = mathOwnedSlice(.source, runeInfo.start, .pos)
        return .newSymbol(text, mathLiteralClass(runeInfo.value))
    }

    mtd parseAtom()->*MathNode fail
    {
        let base       = try .parsePrimary()
        var sub, sup: *MathNode?
        var limitsMode = MathLimitsMode.Automatic

        while true
        {
            .skipMathSpaces()
            if try .consumeControlWord("limits")
            {
                limitsMode = .Limits
                continue
            }

            if try .consumeControlWord("nolimits")
            {
                limitsMode = .NoLimits
                continue
            }

            let marker = .peek()
            if marker != '^' and marker != '_' do
                break
            let markerAt = .pos
            .pos += 1
            if marker == '^'
            {
                if sup do
                    try mathFail("math atom already has a superscript", markerAt)
                sup = try .parseRequiredArgument("superscript")
            }
            else
            {
                if sub do
                    try mathFail("math atom already has a subscript", markerAt)
                sub = try .parseRequiredArgument("subscript")
            }
        }

        if not sub and not sup and limitsMode == .Automatic do
            return base

        if not sub and not sup
        {
            base.limitsMode = limitsMode
            return base
        }

        let scripts = .newNode(.Scripts)
        scripts.limitsMode = limitsMode
        scripts.children.add(base)
        if sub
        {
            scripts.children.add(sub)
            scripts.flag = true
        }

        if sup
        {
            scripts.children.add(sup)
            scripts.flag2 = true
        }

        scripts.atomClass = base.atomClass
        return scripts
    }
}

impl MathExpression
{
    // Releases the parsed expression tree and its cached layout data.
    mtd opDrop()
    {
        .nodes.clear()
    }

    // Produces an independent copy of the parsed expression.
    //
    // The owned node array is copied deeply. The root and every edge are rebound
    // through stable parse-time node identifiers.
    mtd opPostCopy()
    {
        if .nodes.isEmpty() do
            return

        let rootId = .root.id
        for nodeRef in .nodes
        {
            let node = nodeRef!
            for idx in node.children.count
            {
                let childId = node.children[idx].id
                node.children[idx] = .nodes[childId]!
            }

            // Layout caches contain non-owning text views and are cheap to rebuild.
            // Clearing them prevents a post-layout copy from retaining views into
            // the original expression.
            node.metrics.width, node.metrics.ascent, node.metrics.descent = 0
            node.offsets.clear()
            node.rules.clear()
            node.draws.clear()
            node.paths.clear()
        }

        .root = .nodes[rootId]!
    }

    // Parses a reusable TeX-like mathematical expression.
    //
    // Malformed or unsupported input is reported through `fail`, with the byte offset where
    // parsing stopped.
    func parse(source: string)->MathExpression fail
    {
        var result: retval
        result.source = source

        var parser: MathParser
        parser.expression = &result
        parser.source     = result.source.toString()
        parser.pos        = 0
        result.root       = try parser.parseRow()
        parser.skipMathSpaces()
        if not parser.eof() do
            try mathFail("math parser stopped before the end of the expression", parser.pos)
        return result
    }

    // Returns the original TeX-like source.
    mtd const sourceText()->string => .source.toString()

    // Returns the number of parsed nodes, for diagnostics and cache accounting.
    mtd const nodeCount()->u64 => .nodes.count
}
