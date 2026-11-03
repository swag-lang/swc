#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func makeMathTestFont(cache: *FontCache)->*Font
{
    let face = expect TypeFace.load(getTestDataPath("segoeui.ttf"))
    return cache.createFont(face, 36, .Bitmap)
}

private func assertMathParses(source: string)
{
    discard expect MathExpression.parse(source)
}

private func assertMathSyntaxError(source: string, contains: string, seek: u64)
{
    var errOutcome: Swag.Error
    discard catch MathExpression.parse(source) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
    Swag.require((err is Errors.SyntaxError))
    let syntax = assume cast (*Errors.SyntaxError, err)
    Swag.require(syntax.seek == seek)
    Swag.require(syntax.message != null)
    Swag.require(Utf8.indexOf(syntax.message, contains) != Swag.U64.Max)
}

private func assertMathDelimiterPaths(font: *Font, source: string, leftKind, rightKind: MathPathKind)
{
    var expression = expect MathExpression.parse(source)
    discard expression.measure(font)
    let delimiters = expression.root.children[0]
    Swag.require(delimiters.kind == .Delimited)
    Swag.require(delimiters.paths.count == 2)
    Swag.require(delimiters.paths[0].kind == leftKind)
    Swag.require(delimiters.paths[1].kind == rightKind)
    Swag.require(delimiters.paths[0].rect.height > cast(f32, font.size))
    Swag.require(delimiters.paths[1].rect.height == delimiters.paths[0].rect.height)
}

#test
{
    var expression = expect MathExpression.parse(#raw "x^2 + y_1 = \alpha")

    Swag.require(expression.sourceText() == #raw "x^2 + y_1 = \alpha")
    Swag.require(expression.nodeCount() >= 10)
    Swag.require(expression.root.kind == .Row)
    Swag.require(expression.root.children.count == 5)
    Swag.require(expression.root.children[0].kind == .Scripts)
    Swag.require(expression.root.children[2].kind == .Scripts)
    Swag.require(expression.root.children[4].text == "\u03B1")
}

#test
{
    const Commands = [
        #raw "\alpha+\beta+\gamma+\delta+\epsilon+\varepsilon+\theta+\vartheta+\lambda+\mu+\pi+\varpi+\rho+\varrho+\sigma+\phi+\varphi+\omega",
        #raw "\Gamma+\Delta+\Theta+\Lambda+\Xi+\Pi+\Sigma+\Upsilon+\Phi+\Psi+\Omega",
        #raw "a\times b\div c\cdot d\pm e\mp f\oplus g\otimes h",
        #raw "a\le b\ge c\ne d\approx e\sim f\equiv g\in A\notin B\subseteq C\supseteq D",
        #raw "A\to B\leftarrow C\leftrightarrow D\Rightarrow E\Leftrightarrow F\mapsto G",
        #raw "\infty+\partial+\nabla+\forall+\exists+\neg+\emptyset+\ell+\hbar+\Re+\Im+\aleph",
        #raw "\sin x+\cos y+\tan z+\log n+\ln n+\exp x+\det A+\gcd(a,b)",
        #raw "\lvert x\rvert+\lVert v\rVert+\vert y\vert+\Vert z\Vert+\|w\|"]

    for commandLine in Commands do
        assertMathParses(commandLine)
}

#test
{
    var cache: FontCache
    let font     = makeMathTestFont(&cache)
    var plain    = expect MathExpression.parse("x")
    var scripted = expect MathExpression.parse(#raw "x_i^2")

    let plainMetrics    = plain.measure(font)
    let scriptedMetrics = scripted.measure(font)
    Swag.require(plainMetrics.width > 0)
    Swag.require(plainMetrics.height() > 0)
    Swag.require(scriptedMetrics.width > plainMetrics.width)
    Swag.require(scriptedMetrics.ascent > plainMetrics.ascent)
    Swag.require(scriptedMetrics.descent > plainMetrics.descent)
}

#test
{
    var cache: FontCache
    let font     = makeMathTestFont(&cache)
    var original = expect MathExpression.parse(#raw "\frac{x_1+1}{\sqrt{y}}")
    discard original.measure(font)
    var copied = original

    Swag.require(copied.root != original.root)
    Swag.require(copied.nodes[0] != original.nodes[0])
    Swag.require(copied.nodeCount() == original.nodeCount())
    Swag.require(copied.sourceText() == original.sourceText())
    var originalPathCount, copiedPathCount = 0'u64
    for nodeRef in original.nodes do
        originalPathCount += nodeRef!.paths.count
    for nodeRef in copied.nodes do
        copiedPathCount += nodeRef!.paths.count
    Swag.require(originalPathCount == 1)
    Swag.require(copiedPathCount == 0)
    let originalMetrics = original.measure(font)
    let copiedMetrics   = copied.measure(font)
    Swag.require(Math.isEqualEpsilon(originalMetrics.width, copiedMetrics.width, 0.001))
    Swag.require(Math.isEqualEpsilon(originalMetrics.height(), copiedMetrics.height(), 0.001))
    for nodeRef in copied.nodes do
        copiedPathCount += nodeRef!.paths.count
    Swag.require(copiedPathCount == 1)
}

#test
{
    var cache: FontCache
    let font     = makeMathTestFont(&cache)
    var simple   = expect MathExpression.parse("ab")
    var fraction = expect MathExpression.parse(#raw "\frac{a+b}{c-d}")
    var binomial = expect MathExpression.parse(#raw "\binom{n}{k}")

    let simpleMetrics   = simple.measure(font)
    let fractionMetrics = fraction.measure(font)
    let binomialMetrics = binomial.measure(font)
    Swag.require(fractionMetrics.height() > simpleMetrics.height() * 1.5)
    Swag.require(fraction.root.children[0].kind == .Fraction)
    Swag.require(fraction.root.children[0].rules.count == 1)
    Swag.require(binomialMetrics.height() > simpleMetrics.height())
    Swag.require(binomial.root.children[0].kind == .Delimited)
    Swag.require(binomial.root.children[0].children[0].rules.isEmpty())
}

#test
{
    var cache: FontCache
    let font    = makeMathTestFont(&cache)
    var square  = expect MathExpression.parse(#raw "\sqrt{x+1}")
    var indexed = expect MathExpression.parse(#raw "\sqrt[3]{x+1}")

    let squareMetrics  = square.measure(font)
    let indexedMetrics = indexed.measure(font)
    Swag.require(square.root.children[0].kind == .Radical)
    Swag.require(square.root.children[0].rules.isEmpty())
    Swag.require(square.root.children[0].paths.count == 1)
    Swag.require(square.root.children[0].paths[0].kind == .Radical)
    Swag.require(indexed.root.children[0].children.count == 2)
    Swag.require(indexedMetrics.ascent >= squareMetrics.ascent)
}

#test
{
    var cache: FontCache
    let font     = makeMathTestFont(&cache)
    var fixed    = expect MathExpression.parse("(x)")
    var stretchy = expect MathExpression.parse(#raw "\left(\frac{a}{b}\right)")

    let fixedMetrics    = fixed.measure(font)
    let stretchyMetrics = stretchy.measure(font)
    let delimiters      = stretchy.root.children[0]
    Swag.require(delimiters.kind == .Delimited)
    Swag.require(delimiters.draws.isEmpty())
    Swag.require(delimiters.paths.count == 2)
    Swag.require(delimiters.paths[0].kind == .LeftParenthesis)
    Swag.require(delimiters.paths[1].kind == .RightParenthesis)
    Swag.require(stretchyMetrics.height() > fixedMetrics.height())
    Swag.require(delimiters.paths[0].rect.height > cast(f32, font.size))
}

#test
{
    var cache: FontCache
    let font = makeMathTestFont(&cache)
    assertMathDelimiterPaths(font, #raw "\left[\frac{a}{b}\right]", .LeftBracket, .RightBracket)
    assertMathDelimiterPaths(font, #raw "\left\lbrace\frac{a}{b}\right\rbrace", .LeftBrace, .RightBrace)
    assertMathDelimiterPaths(font, #raw "\left\langle\frac{a}{b}\right\rangle", .LeftAngle, .RightAngle)
    assertMathDelimiterPaths(font, #raw "\left\lfloor\frac{a}{b}\right\rfloor", .LeftFloor, .RightFloor)
    assertMathDelimiterPaths(font, #raw "\left\lceil\frac{a}{b}\right\rceil", .LeftCeiling, .RightCeiling)
    assertMathDelimiterPaths(font, #raw "\left\lvert\frac{a}{b}\right\rvert", .Bar, .Bar)
    assertMathDelimiterPaths(font, #raw "\left\lVert\frac{a}{b}\right\rVert", .DoubleBar, .DoubleBar)
}

#test
{
    var cache: FontCache
    let font     = makeMathTestFont(&cache)
    var display  = expect MathExpression.parse(#raw "\sum_{i=0}^{n} i^2")
    var text     = expect MathExpression.parse(#raw "\sum_{i=0}^{n} i^2")
    var integral = expect MathExpression.parse(#raw "\int_{0}^{1} x\,dx")

    let displayMetrics  = display.measure(font, {style: .Display})
    let textMetrics     = text.measure(font, {style: .Text})
    let integralMetrics = integral.measure(font, {style: .Display})
    Swag.require(displayMetrics.height() > textMetrics.height())
    Swag.require(textMetrics.width > displayMetrics.width * 0.75)
    Swag.require(integralMetrics.width > 0)

    let sumScripts = display.root.children[0]
    let intScripts = integral.root.children[0]
    Swag.require(sumScripts.offsets[1].x < sumScripts.children[0].metrics.width)
    Swag.require(intScripts.offsets[1].x >= intScripts.children[0].metrics.width)
}

#test
{
    var cache: FontCache
    let font     = makeMathTestFont(&cache)
    var tight    = expect MathExpression.parse("ab")
    var binary   = expect MathExpression.parse("a+b")
    var relation = expect MathExpression.parse("a=b")
    var spaced   = expect MathExpression.parse(#raw "a\quad b")
    var negative = expect MathExpression.parse(#raw "a\!b")

    let tightWidth    = tight.measure(font).width
    let binaryWidth   = binary.measure(font).width
    let relationWidth = relation.measure(font).width
    let spacedWidth   = spaced.measure(font).width
    let negativeWidth = negative.measure(font).width
    Swag.require(binaryWidth > tightWidth)
    Swag.require(relationWidth > binaryWidth)
    Swag.require(spacedWidth > tightWidth + cast(f32, font.size) * 0.9)
    Swag.require(negativeWidth < tightWidth)
}

#test
{
    var cache: FontCache
    let font          = makeMathTestFont(&cache)
    var matrix        = expect MathExpression.parse(#raw "\begin{matrix}a&b\\c&d\end{matrix}")
    var parenthesized = expect MathExpression.parse(#raw "\begin{pmatrix}1&0\\0&1\end{pmatrix}")
    var cases         = expect MathExpression.parse(#raw "\begin{cases}x&x>0\\-x&x\le0\end{cases}")

    let matrixMetrics = matrix.measure(font)
    let parenMetrics  = parenthesized.measure(font)
    let casesMetrics  = cases.measure(font)
    let matrixNode    = matrix.root.children[0]
    Swag.require(matrixNode.kind == .Matrix)
    Swag.require(matrixNode.rowLengths.count == 2)
    Swag.require(matrixNode.rowLengths[0] == 2)
    Swag.require(matrixNode.children.count == 4)
    Swag.require(matrixMetrics.width > 0 and matrixMetrics.height() > font.height)
    Swag.require(parenMetrics.width > matrixMetrics.width)
    Swag.require(casesMetrics.height() > font.height)
    Swag.require(parenthesized.root.children[0].paths.count == 2)
    Swag.require(cases.root.children[0].paths.count == 1)
    Swag.require(cases.root.children[0].paths[0].kind == .LeftBrace)
}

#test
{
    const Environments = [
        #raw "\begin{bmatrix}a&b\\c&d\end{bmatrix}",
        #raw "\begin{Bmatrix}a&b\\c&d\end{Bmatrix}",
        #raw "\begin{vmatrix}a&b\\c&d\end{vmatrix}",
        #raw "\begin{Vmatrix}a&b\\c&d\end{Vmatrix}",
        #raw "\begin{aligned}a&=b+c\\d&=e-f\end{aligned}"]
    for source in Environments do
        assertMathParses(source)
}

#test
{
    var cache: FontCache
    let font         = makeMathTestFont(&cache)
    var plain        = expect MathExpression.parse("x")
    var accents      = expect MathExpression.parse(#raw "\hat{x}+\tilde{y}+\vec{v}+\dot{x}+\ddot{x}+\bar{q}+\overline{AB}+\underline{z}")
    let plainMetrics = plain.measure(font)
    let metrics      = accents.measure(font)
    Swag.require(metrics.width > 0)
    Swag.require(metrics.ascent > plainMetrics.ascent)

    var ruleCount, pathCount = 0'u64
    var sawHat, sawTilde, sawVector: bool
    for nodeRef in accents.nodes
    {
        let node = unwrap nodeRef
        if node.kind == .Accent
        {
            ruleCount += node.rules.count
            pathCount += node.paths.count
            for path in node.paths
            {
                if path.kind == .Hat do
                    sawHat = true
                if path.kind == .Tilde do
                    sawTilde = true
                if path.kind == .Vector do
                    sawVector = true
            }
        }
    }

    Swag.require(ruleCount == 3)
    Swag.require(pathCount == 3)
    Swag.require(sawHat and sawTilde and sawVector)
}

#test
{
    var cache: FontCache
    let font    = makeMathTestFont(&cache)
    var styled  = expect MathExpression.parse(#raw "\mathrm{d}x+\mathit{ABC}+\mathbf{x}+\boldsymbol{\alpha}+\text{for all }x")
    let metrics = styled.measure(font)
    Swag.require(metrics.width > 0)

    var sawRoman, sawItalic, sawBold, sawBoldItalic: bool
    for nodeRef in styled.nodes
    {
        let node = unwrap nodeRef
        if node.kind != .Style do
            continue
        if node.fontVariant == .Roman do
            sawRoman = true
        if node.fontVariant == .Italic do
            sawItalic = true
        if node.fontVariant == .Bold do
            sawBold = true
        if node.fontVariant == .BoldItalic do
            sawBoldItalic = true
    }

    Swag.require(sawRoman and sawItalic and sawBold and sawBoldItalic)
}

#test
{
    assertMathSyntaxError(#raw "\unknown{x}", "does not support command '\\unknown'", 0)
    assertMathSyntaxError(#raw "\frac{a}", "fraction denominator needs an argument", 8)
    assertMathSyntaxError("{a", "group has no closing '}'", 0)
    assertMathSyntaxError("a}", "closing '}' without a matching group", 1)
    assertMathSyntaxError("^2", "script marker '^' has no base", 0)
    assertMathSyntaxError("x^1^2", "already has a superscript", 3)
    assertMathSyntaxError(#raw "\left(x", "has no matching '\\right'", 7)
    assertMathSyntaxError(#raw "\right)", "has no matching '\\left'", 0)
    assertMathSyntaxError(#raw "\begin{grid}a\end{grid}", "does not support environment 'grid'", 6)
    assertMathSyntaxError(#raw "\begin{matrix}a\end{pmatrix}", "ends with '\\end{pmatrix}'", 28)
    assertMathSyntaxError("a&b", "alignment marker '&' is outside a matrix", 1)
}

#test
{
    var cache:   FontCache
    let font       = makeMathTestFont(&cache)
    var expression = expect MathExpression.parse(#raw "\left(\frac{x_i^2}{\sqrt{1+x}}\right)")
    var painter: Painter
    painter.begin()
    let metrics = painter.drawMath(20, 30, &expression, font, Argb.MidnightBlue)
    painter.end()

    Swag.require(metrics.width > 0 and metrics.height() > 0)
    Swag.require(not painter.vertexBuffer.isEmpty())
    Swag.require(not painter.commandBuffer.isEmpty())
}

#test
{
    const PathOnlyExpressions = [
        #raw "\sqrt{}",
        #raw "\left(\right)",
        #raw "\left[\right]",
        #raw "\left\lbrace\right\rbrace",
        #raw "\left\langle\right\rangle",
        #raw "\left\lfloor\right\rfloor",
        #raw "\left\lceil\right\rceil",
        #raw "\left\lvert\right\rvert",
        #raw "\left\lVert\right\rVert",
        #raw "\hat{}",
        #raw "\tilde{}",
        #raw "\vec{}"]

    var cache:   FontCache
    let font = makeMathTestFont(&cache)
    var painter: Painter
    painter.begin()
    for source, idx in PathOnlyExpressions
    {
        var expression     = expect MathExpression.parse(source)
        let oldVertexCount = painter.vertexBuffer.count
        painter.drawMath(0, cast(f32, idx) * 48, &expression, font, Argb.Black)
        Swag.require(painter.vertexBuffer.count > oldVertexCount)
    }

    painter.end()
}

#test
{
    var cache:   FontCache
    let font = makeMathTestFont(&cache)
    var painter: Painter
    painter.begin()
    var errOutcome: Swag.Error
    var metrics:    #decltype(expect painter.drawMathLatex(0, 0, #raw "\frac{1}{2}", font, Argb.Black))
    catch { metrics = try painter.drawMathLatex(0, 0, #raw "\frac{1}{2}", font, Argb.Black) } as errOutcome
    let err = errOutcome.value()
    painter.end()

    Swag.require(err == null)
    Swag.require(metrics.width > 0)
    Swag.require(metrics.height() > font.height)
}
