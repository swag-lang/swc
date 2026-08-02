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

// Result of mathematical layout. The baseline is `ascent` pixels below the top.
struct MathMetrics
{
    width:   f32     // Horizontal extent in pixels.
    ascent:  f32     // Distance from the baseline to the top edge, in pixels.
    descent: f32     // Distance from the baseline to the bottom edge, in pixels.
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
    style:             MathStyle = Display     // Root style used to begin layout.
    scriptScale:       f32       = 0.72        // Font-size multiplier for first-level scripts.
    scriptScriptScale: f32       = 0.55        // Font-size multiplier for nested scripts.
    ruleThicknessEm:   f32       = 0.055       // Fraction and radical rule thickness in em.
    minRuleThickness:  f32       = 1.0         // Minimum visible rule thickness in pixels.
    rowGapEm:          f32       = 0.32        // Vertical gap between matrix rows in em.
    columnGapEm:       f32       = 0.65        // Horizontal gap between matrix columns in em.
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
    font:  *Font = undefined
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
        source: String                    // Expression text the tree was parsed from.
        nodes:  ArrayPtr'MathNode         // Pool owning every node of the tree.
        root:   *MathNode = undefined     // Root of the tree, set by 'parse'.
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
    expression: *MathExpression = undefined
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
        result = @mkstring(@dataof(source) + start, end - start)
    return result
}

private func mathIsAsciiLetter(c: u8)->bool
{
    return c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z'
}

internal func mathStyleScale(style: MathStyle, options: const &MathLayoutOptions)->f32
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
    case '+', '-', '*', '/', '\u00D7'rune, '\u00F7'rune:          return .Bin
    case '=', '<', '>', '\u2260'rune, '\u2264'rune, '\u2265'rune: return .Rel
    case '(', '[', '{':                                           return .Open
    case ')', ']', '}':                                           return .Close
    case ',', ';', ':':                                           return .Punct
    case '|':                                                     return .Rel
    }

    return .Ord
}

private func mathIsAsciiVariable(text: string)->bool
{
    if @countof(text) != 1 do
        return false
    return mathIsAsciiLetter((notnull @dataof(text))[0])
}

private func mathSymbol(text: string, atomClass = MathAtomClass.Ord, large = false, limitsMode = MathLimitsMode.Automatic)->MathSymbolSpec
{
    return {text: text, atomClass: atomClass, found: true, largeOperator: large, limitsMode: limitsMode}
}

// Common LaTeX math commands. Unicode is the interchange layer between the
// parser and Pixel's font renderer, so a font can provide its best matching glyph.
private func mathCommandSymbol(command: string)->MathSymbolSpec
{
    // Greek lowercase
    if command == "alpha" do return mathSymbol("\u03B1")
    if command == "beta" do return mathSymbol("\u03B2")
    if command == "gamma" do return mathSymbol("\u03B3")
    if command == "delta" do return mathSymbol("\u03B4")
    if command == "epsilon" do return mathSymbol("\u03F5")
    if command == "varepsilon" do return mathSymbol("\u03B5")
    if command == "zeta" do return mathSymbol("\u03B6")
    if command == "eta" do return mathSymbol("\u03B7")
    if command == "theta" do return mathSymbol("\u03B8")
    if command == "vartheta" do return mathSymbol("\u03D1")
    if command == "iota" do return mathSymbol("\u03B9")
    if command == "kappa" do return mathSymbol("\u03BA")
    if command == "lambda" do return mathSymbol("\u03BB")
    if command == "mu" do return mathSymbol("\u03BC")
    if command == "nu" do return mathSymbol("\u03BD")
    if command == "xi" do return mathSymbol("\u03BE")
    if command == "pi" do return mathSymbol("\u03C0")
    if command == "varpi" do return mathSymbol("\u03D6")
    if command == "rho" do return mathSymbol("\u03C1")
    if command == "varrho" do return mathSymbol("\u03F1")
    if command == "sigma" do return mathSymbol("\u03C3")
    if command == "varsigma" do return mathSymbol("\u03C2")
    if command == "tau" do return mathSymbol("\u03C4")
    if command == "upsilon" do return mathSymbol("\u03C5")
    if command == "phi" do return mathSymbol("\u03D5")
    if command == "varphi" do return mathSymbol("\u03C6")
    if command == "chi" do return mathSymbol("\u03C7")
    if command == "psi" do return mathSymbol("\u03C8")
    if command == "omega" do return mathSymbol("\u03C9")

    // Greek uppercase
    if command == "Gamma" do return mathSymbol("\u0393")
    if command == "Delta" do return mathSymbol("\u0394")
    if command == "Theta" do return mathSymbol("\u0398")
    if command == "Lambda" do return mathSymbol("\u039B")
    if command == "Xi" do return mathSymbol("\u039E")
    if command == "Pi" do return mathSymbol("\u03A0")
    if command == "Sigma" do return mathSymbol("\u03A3")
    if command == "Upsilon" do return mathSymbol("\u03A5")
    if command == "Phi" do return mathSymbol("\u03A6")
    if command == "Psi" do return mathSymbol("\u03A8")
    if command == "Omega" do return mathSymbol("\u03A9")

    // Binary operators
    if command == "pm" do return mathSymbol("\u00B1", .Bin)
    if command == "mp" do return mathSymbol("\u2213", .Bin)
    if command == "times" do return mathSymbol("\u00D7", .Bin)
    if command == "div" do return mathSymbol("\u00F7", .Bin)
    if command == "cdot" do return mathSymbol("\u22C5", .Bin)
    if command == "ast" do return mathSymbol("\u2217", .Bin)
    if command == "star" do return mathSymbol("\u22C6", .Bin)
    if command == "circ" do return mathSymbol("\u2218", .Bin)
    if command == "bullet" do return mathSymbol("\u2219", .Bin)
    if command == "cap" do return mathSymbol("\u2229", .Bin)
    if command == "cup" do return mathSymbol("\u222A", .Bin)
    if command == "setminus" do return mathSymbol("\u2216", .Bin)
    if command == "land" or command == "wedge" do return mathSymbol("\u2227", .Bin)
    if command == "lor" or command == "vee" do return mathSymbol("\u2228", .Bin)
    if command == "oplus" do return mathSymbol("\u2295", .Bin)
    if command == "ominus" do return mathSymbol("\u2296", .Bin)
    if command == "otimes" do return mathSymbol("\u2297", .Bin)
    if command == "oslash" do return mathSymbol("\u2298", .Bin)

    // Relations
    if command == "le" or command == "leq" do return mathSymbol("\u2264", .Rel)
    if command == "ge" or command == "geq" do return mathSymbol("\u2265", .Rel)
    if command == "ne" or command == "neq" do return mathSymbol("\u2260", .Rel)
    if command == "approx" do return mathSymbol("\u2248", .Rel)
    if command == "sim" do return mathSymbol("\u223C", .Rel)
    if command == "simeq" do return mathSymbol("\u2243", .Rel)
    if command == "equiv" do return mathSymbol("\u2261", .Rel)
    if command == "propto" do return mathSymbol("\u221D", .Rel)
    if command == "in" do return mathSymbol("\u2208", .Rel)
    if command == "notin" do return mathSymbol("\u2209", .Rel)
    if command == "ni" do return mathSymbol("\u220B", .Rel)
    if command == "subset" do return mathSymbol("\u2282", .Rel)
    if command == "supset" do return mathSymbol("\u2283", .Rel)
    if command == "subseteq" do return mathSymbol("\u2286", .Rel)
    if command == "supseteq" do return mathSymbol("\u2287", .Rel)
    if command == "parallel" do return mathSymbol("\u2225", .Rel)
    if command == "perp" do return mathSymbol("\u22A5", .Rel)
    if command == "mid" do return mathSymbol("\u2223", .Rel)
    if command == "models" do return mathSymbol("\u22A8", .Rel)

    // Arrows
    if command == "to" or command == "rightarrow" do return mathSymbol("\u2192", .Rel)
    if command == "leftarrow" do return mathSymbol("\u2190", .Rel)
    if command == "leftrightarrow" do return mathSymbol("\u2194", .Rel)
    if command == "Rightarrow" do return mathSymbol("\u21D2", .Rel)
    if command == "Leftarrow" do return mathSymbol("\u21D0", .Rel)
    if command == "Leftrightarrow" do return mathSymbol("\u21D4", .Rel)
    if command == "mapsto" do return mathSymbol("\u21A6", .Rel)
    if command == "uparrow" do return mathSymbol("\u2191", .Rel)
    if command == "downarrow" do return mathSymbol("\u2193", .Rel)

    // Large operators
    if command == "sum" do return mathSymbol("\u2211", .Op, true, .Limits)
    if command == "prod" do return mathSymbol("\u220F", .Op, true, .Limits)
    if command == "coprod" do return mathSymbol("\u2210", .Op, true, .Limits)
    if command == "int" do return mathSymbol("\u222B", .Op, true, .NoLimits)
    if command == "iint" do return mathSymbol("\u222C", .Op, true, .NoLimits)
    if command == "iiint" do return mathSymbol("\u222D", .Op, true, .NoLimits)
    if command == "oint" do return mathSymbol("\u222E", .Op, true, .NoLimits)
    if command == "bigcap" do return mathSymbol("\u22C2", .Op, true, .Limits)
    if command == "bigcup" do return mathSymbol("\u22C3", .Op, true, .Limits)
    if command == "bigwedge" do return mathSymbol("\u22C0", .Op, true, .Limits)
    if command == "bigvee" do return mathSymbol("\u22C1", .Op, true, .Limits)

    // Named functions
    if command == "sin" or command == "cos" or command == "tan" or command == "cot" or command == "sec" or command == "csc" or command == "sinh" or command == "cosh" or command == "tanh" or command == "log" or command == "ln" or command == "exp" or command == "lim" or command == "limsup" or command == "liminf" or command == "max" or command == "min" or command == "sup" or command == "inf" or command == "det" or command == "gcd"
    {
        let limits = command == "lim" or command == "limsup" or command == "liminf" ? MathLimitsMode.Limits : MathLimitsMode.Automatic
        return mathSymbol(command, .Op, false, limits)
    }

    // Delimiters and ordinary symbols
    if command == "lbrace" do return mathSymbol("{", .Open)
    if command == "rbrace" do return mathSymbol("}", .Close)
    if command == "langle" do return mathSymbol("\u27E8", .Open)
    if command == "rangle" do return mathSymbol("\u27E9", .Close)
    if command == "lfloor" do return mathSymbol("\u230A", .Open)
    if command == "rfloor" do return mathSymbol("\u230B", .Close)
    if command == "lceil" do return mathSymbol("\u2308", .Open)
    if command == "rceil" do return mathSymbol("\u2309", .Close)
    if command == "vert" or command == "lvert" do return mathSymbol("|", .Open)
    if command == "rvert" do return mathSymbol("|", .Close)
    if command == "Vert" or command == "lVert" do return mathSymbol("\u2016", .Open)
    if command == "rVert" do return mathSymbol("\u2016", .Close)
    if command == "infty" do return mathSymbol("\u221E")
    if command == "partial" do return mathSymbol("\u2202")
    if command == "nabla" do return mathSymbol("\u2207")
    if command == "forall" do return mathSymbol("\u2200")
    if command == "exists" do return mathSymbol("\u2203")
    if command == "neg" or command == "lnot" do return mathSymbol("\u00AC")
    if command == "emptyset" do return mathSymbol("\u2205")
    if command == "ell" do return mathSymbol("\u2113")
    if command == "hbar" do return mathSymbol("\u210F")
    if command == "Re" do return mathSymbol("\u211C")
    if command == "Im" do return mathSymbol("\u2111")
    if command == "aleph" do return mathSymbol("\u2135")
    if command == "ldots" do return mathSymbol("\u2026", .Inner)
    if command == "cdots" do return mathSymbol("\u22EF", .Inner)

    return {text: ""}
}

private impl MathParser
{
    mtd count()->u64 => @countof(.source)

    mtd eof()->bool => .pos >= .count()

    mtd peek()->u8
    {
        if .eof() do
            return 0
        return (notnull @dataof(.source))[.pos]
    }

    mtd peekAt(offset: u64)->u8
    {
        let at = .pos + offset
        if at >= .count() do
            return 0
        return (notnull @dataof(.source))[at]
    }

    mtd skipMathSpaces()
    {
        while !.eof()
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
            mathFail("math expression ends, but this position needs an atom", .pos)

        let slice    = @mkslice(@dataof(.source) + .pos, .count() - .pos)
        let {c, eat} = Utf8.decodeRune(slice)
        if eat == 0 do
            mathFail("math expression contains an incomplete UTF-8 sequence", .pos)
        result.value = c
        .pos         += eat
        return result
    }

    mtd atControlWord(word: string)->bool
    {
        if .peek() != '\\' do
            return false
        let size = @countof(word)
        if .pos + 1 + size > .count() do
            return false
        let got = @mkstring(@dataof(.source) + .pos + 1, size)
        if got != word do
            return false
        if .pos + 1 + size < .count() and mathIsAsciiLetter((notnull @dataof(.source))[.pos + 1 + size]) do
            return false
        return true
    }

    mtd readCommand()->String fail
    {
        let slash = .pos
        if .peek() != '\\' do
            mathFail("math command needs a leading '\\'", .pos)
        .pos += 1
        if .eof() do
            mathFail("math expression ends after '\\'", slash)

        let start = .pos
        if mathIsAsciiLetter(.peek())
        {
            while mathIsAsciiLetter(.peek()) do
                .pos += 1
        }
        else do
            .pos += 1

        return mathOwnedSlice(.source, start, .pos)
    }

    mtd consumeControlWord(word: string)->bool fail
    {
        if !.atControlWord(word) do
            return false
        discard .readCommand()
        .skipMathSpaces()
        return true
    }

    mtd readRawGroup(label: string)->String fail
    {
        .skipMathSpaces()
        let open = .pos
        if .peek() != '{' do
            mathFail(Format.toString("% needs a '{...}' argument", label), .pos)
        .pos += 1

        let start = .pos
        var depth = 1'u32
        while !.eof()
        {
            let c = .peek()
            if c == '\\'
            {
                .pos += 1
                if !.eof() do
                    .pos += 1
                continue
            }

            if c == '{' do
                depth += 1
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

        mathFail(Format.toString("% has no closing '}'", label), open)
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
                mathFail("math expression has a closing '}' without a matching group", .pos)
            if .peek() == ']' do
                mathFail("math expression has a closing ']' without a matching root index", .pos)
            if .peek() == '&' do
                mathFail("math alignment marker '&' is outside a matrix", .pos)

            row.children.add(.parseAtom())
        }

        return row
    }

    mtd parseRequiredArgument(label: string)->*MathNode fail
    {
        .skipMathSpaces()
        if .eof() do
            mathFail(Format.toString("% needs an argument", label), .pos)
        if .peek() == '{' do
            return .parseGroup()

        // TeX consumes exactly one token for an unbraced argument. In `x_i^2`,
        // this keeps `^2` attached to x instead of accidentally nesting it under i.
        return .parsePrimary()
    }

    mtd parseGroup()->*MathNode fail
    {
        let open = .pos
        if .peek() != '{' do
            mathFail("math group needs an opening '{'", .pos)
        .pos += 1
        let result = .parseRow(.Brace)
        if .peek() != '}' do
            mathFail("math group has no closing '}'", open)
        .pos += 1
        return result
    }

    mtd parseBracketGroup()->*MathNode fail
    {
        let open = .pos
        if .peek() != '[' do
            mathFail("root index needs an opening '['", .pos)
        .pos += 1
        let result = .parseRow(.Bracket)
        if .peek() != ']' do
            mathFail("root index has no closing ']'", open)
        .pos += 1
        return result
    }

    mtd parseDelimiter(label: string)->String fail
    {
        .skipMathSpaces()
        if .eof() do
            mathFail(Format.toString("% needs a delimiter", label), .pos)

        if .peek() == '\\'
        {
            let at      = .pos
            let command = .readCommand()
            let spec    = mathCommandSymbol(command)
            if !spec.found do
                mathFail(Format.toString("% has no delimiter for command '\\%'", label, command), at)
            return spec.text
        }

        let runeInfo = .readRune()
        return mathOwnedSlice(.source, runeInfo.start, .pos)
    }

    mtd parseLeftRight()->*MathNode fail
    {
        let left = .parseDelimiter("'\\left'")
        let body = .parseRow(.Right)
        if !.consumeControlWord("right") do
            mathFail("'\\left' has no matching '\\right'", .pos)
        let right = .parseDelimiter("'\\right'")

        let node = .newNode(.Delimited)
        node.text  = left
        node.text2 = right
        node.children.add(body)
        node.atomClass = .Inner
        return node
    }

    mtd parseFraction(withRule = true)->*MathNode fail
    {
        let numerator   = .parseRequiredArgument("fraction numerator")
        let denominator = .parseRequiredArgument("fraction denominator")
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
        var index: #null *MathNode
        if .peek() == '[' do
            index = .parseBracketGroup()
        let radicand = .parseRequiredArgument("radical")
        let node     = .newNode(.Radical)
        node.children.add(radicand)
        if index
        {
            node.children.add(notnull index)
            node.flag = true
        }

        node.atomClass = .Ord
        return node
    }

    mtd parseStyle(variant: MathFontVariant, label: string)->*MathNode fail
    {
        let child = .parseRequiredArgument(label)
        let node  = .newNode(.Style)
        node.fontVariant = variant
        node.children.add(child)
        return node
    }

    mtd parseAccent(accent: string, under = false, asRule = false)->*MathNode fail
    {
        let child = .parseRequiredArgument("math accent")
        let node  = .newNode(.Accent)
        node.text  = accent
        node.flag  = under
        node.flag2 = asRule
        node.children.add(child)
        return node
    }

    mtd parseOperatorName()->*MathNode fail
    {
        let name = .readRawGroup("'\\operatorname'")
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
        else do
            return matrix

        let delimited = .newNode(.Delimited)
        delimited.text  = left
        delimited.text2 = right
        delimited.children.add(matrix)
        delimited.atomClass = .Inner
        return delimited
    }

    mtd parseEnvironment()->*MathNode fail
    {
        let beginAt     = .pos
        let environment = .readRawGroup("'\\begin'")
        if environment != "matrix" and environment != "pmatrix" and environment != "bmatrix" and environment != "Bmatrix" and environment != "vmatrix" and environment != "Vmatrix" and environment != "cases" and environment != "aligned" do
            mathFail(Format.toString("math renderer does not support environment '%'", environment), beginAt)

        let matrix = .newNode(.Matrix)
        matrix.atomClass = .Inner
        var columnsInRow = 0'u32

        while true
        {
            let cell = .parseRow(.Matrix)
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
                discard .readCommand()
                let closeEnvironment = .readRawGroup("'\\end'")
                if closeEnvironment != environment do
                    mathFail(Format.toString("'\\begin{%}' ends with '\\end{%}'", environment, closeEnvironment), .pos)
                matrix.rowLengths.add(columnsInRow)
                break
            }

            mathFail(Format.toString("math environment '%' has no matching '\\end{%}'", environment, environment), beginAt)
        }

        return .wrapMatrix(matrix, environment)
    }

    mtd parseCommand()->*MathNode fail
    {
        let at      = .pos
        let command = .readCommand()

        if command == "frac" or command == "dfrac" or command == "tfrac" do
            return .parseFraction()
        if command == "binom"
        {
            let fraction = .parseFraction(false)
            let node     = .newNode(.Delimited)
            node.text  = "("
            node.text2 = ")"
            node.children.add(fraction)
            node.atomClass = .Inner
            return node
        }

        if command == "sqrt" do
            return .parseRadical()
        if command == "left" do
            return .parseLeftRight()
        if command == "right" do
            mathFail("'\\right' has no matching '\\left'", at)
        if command == "begin" do
            return .parseEnvironment()
        if command == "end" do
            mathFail("'\\end' has no matching '\\begin'", at)
        if command == "operatorname" do
            return .parseOperatorName()
        if command == "text" or command == "textrm"
        {
            let text = .readRawGroup(Format.toString("'\\%'", command))
            return .newSymbol(text)
        }

        if command == "mathrm" do return .parseStyle(.Roman, "'\\mathrm'")
        if command == "mathit" do return .parseStyle(.Italic, "'\\mathit'")
        if command == "mathbf" do return .parseStyle(.Bold, "'\\mathbf'")
        if command == "boldsymbol" or command == "bm" do return .parseStyle(.BoldItalic, Format.toString("'\\%'", command))

        if command == "hat" or command == "widehat" do return .parseAccent("^")
        if command == "tilde" or command == "widetilde" do return .parseAccent("~")
        if command == "bar" do return .parseAccent("\u00AF")
        if command == "vec" do return .parseAccent("\u2192")
        if command == "dot" do return .parseAccent("\u02D9")
        if command == "ddot" do return .parseAccent("\u00A8")
        if command == "overline" do return .parseAccent("", false, true)
        if command == "underline" do return .parseAccent("", true, true)

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
        if command == "," do space = 3.0 / 18.0
        elif command == ":" do space = 4.0 / 18.0
        elif command == ";" do space = 5.0 / 18.0
        elif command == "!" do space = -3.0 / 18.0
        elif command == " " do space = 1.0 / 3.0
        elif command == "quad" do space = 1.0
        elif command == "qquad" do space = 2.0
        if space != 0
        {
            let node = .newNode(.Space)
            node.spaceEm = space
            return node
        }

        // Escaped TeX punctuation is literal.
        if command == "{" do return .newSymbol("{", .Open)
        if command == "}" do return .newSymbol("}", .Close)
        if command == "_" do return .newSymbol("_")
        if command == "^" do return .newSymbol("^")
        if command == "%" do return .newSymbol("%")
        if command == "#" do return .newSymbol("#")
        if command == "&" do return .newSymbol("&")
        if command == "$" do return .newSymbol("$")
        if command == "|" do return .newSymbol("\u2016", .Open)
        if command == "\\" do
            mathFail("math row break '\\\\' is outside a matrix", at)

        mathFail(Format.toString("math renderer does not support command '\\%'", command), at)
        unreachable
    }

    mtd parsePrimary()->*MathNode fail
    {
        .skipMathSpaces()
        let at = .pos
        if .eof() do
            mathFail("math expression ends, but this position needs an atom", at)

        if .peek() == '{' do
            return .parseGroup()
        if .peek() == '\\' do
            return .parseCommand()
        if .peek() == '^' or .peek() == '_' do
            mathFail(Format.toString("math script marker '%' has no base", @mkstring(@dataof(.source) + .pos, 1)), at)
        if .peek() == '~'
        {
            .pos += 1
            let node = .newNode(.Space)
            node.spaceEm = 1.0 / 3.0
            return node
        }

        let runeInfo = .readRune()
        let text     = mathOwnedSlice(.source, runeInfo.start, .pos)
        return .newSymbol(text, mathLiteralClass(runeInfo.value))
    }

    mtd parseAtom()->*MathNode fail
    {
        let base       = .parsePrimary()
        var sub, sup: #null *MathNode
        var limitsMode = MathLimitsMode.Automatic

        while true
        {
            .skipMathSpaces()
            if .consumeControlWord("limits")
            {
                limitsMode = .Limits
                continue
            }

            if .consumeControlWord("nolimits")
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
                    mathFail("math atom already has a superscript", markerAt)
                sup = .parseRequiredArgument("superscript")
            }
            else
            {
                if sub do
                    mathFail("math atom already has a subscript", markerAt)
                sub = .parseRequiredArgument("subscript")
            }
        }

        if !sub and !sup and limitsMode == .Automatic do
            return base

        if !sub and !sup
        {
            base.limitsMode = limitsMode
            return base
        }

        let scripts = .newNode(.Scripts)
        scripts.limitsMode = limitsMode
        scripts.children.add(base)
        if sub
        {
            scripts.children.add(notnull sub)
            scripts.flag = true
        }

        if sup
        {
            scripts.children.add(notnull sup)
            scripts.flag2 = true
        }

        scripts.atomClass = base.atomClass
        return scripts
    }
}

public impl MathExpression
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
            let node = notnull nodeRef
            for [idx] in node.children.count
            {
                let childId = node.children[idx].id
                node.children[idx] = notnull .nodes[childId]
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

        .root = notnull .nodes[rootId]
    }

    // Parse a reusable TeX-like mathematical expression.
    func parse(source: string)->MathExpression fail
    {
        var result: retval
        result.source = source

        var parser: MathParser = undefined
        parser.expression = &result
        parser.source     = result.source.toString()
        parser.pos        = 0
        result.root       = parser.parseRow()
        parser.skipMathSpaces()
        if !parser.eof() do
            mathFail("math parser stopped before the end of the expression", parser.pos)
        return result
    }

    // Original TeX-like source.
    mtd const sourceText()->string => .source.toString()

    // Number of parsed nodes, useful for diagnostics and cache accounting.
    mtd const nodeCount()->u64 => .nodes.count
}
