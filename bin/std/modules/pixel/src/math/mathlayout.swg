#global public

using Core

private func mathIsSingleLetter(text: string)->bool
{
    if @countof(text) == 0 do
        return false
    let {c, eat} = Utf8.decodeRune(cast(const [..] u8) text)
    return eat == @countof(text) and Unicode.isLetter(c)
}

private func mathResolveFont(baseFont: *Font, variant: MathFontVariant, text: string)->*Font
{
    var bold   = baseFont.forceBold
    var italic = baseFont.forceItalic

    switch variant
    {
    case .Roman:
        bold, italic = false

    case .Italic:
        italic = true

    case .Bold:
        bold   = true
        italic = false

    case .BoldItalic:
        bold, italic = true

    case .Default:

        // TeX sets single-letter variables in math italic, while numbers,
        // punctuation, operators and multi-letter text stay upright.
        if mathIsSingleLetter(text) do
            italic = true
    }

    if bold == baseFont.forceBold and italic == baseFont.forceItalic do
        return baseFont
    return baseFont.owner.createFont(baseFont.cache.typeFace, baseFont.size, baseFont.renderMode(), bold, italic)
}

private func mathRuleThickness(font: *Font, options: const &MathLayoutOptions, scale: f32)->f32
{
    return Math.max(options.minRuleThickness, cast(f32) font.size * options.ruleThicknessEm * scale)
}

private func mathNormalizedClass(row: *MathNode, index: u64)->MathAtomClass
{
    let node = row.children[index]
    var cls  = node.atomClass
    if cls != .Bin do
        return cls

    // A binary operator at a boundary, after another operator/relation/opening,
    // or before a relation/closing/punctuation is unary/ordinary in TeX spacing.
    var prev = MathAtomClass.Open
    var next = MathAtomClass.Close
    var hasPrev, hasNext: bool

    var p = cast(s64) index - 1
    while p >= 0
    {
        let candidate = row.children[cast(u64) p]
        if candidate.kind != .Space
        {
            prev    = candidate.atomClass
            hasPrev = true
            break
        }

        p -= 1
    }

    var n = index + 1
    while n < row.children.count
    {
        let candidate = row.children[n]
        if candidate.kind != .Space
        {
            next    = candidate.atomClass
            hasNext = true
            break
        }

        n += 1
    }

    if !hasPrev or prev == .Bin or prev == .Op or prev == .Rel or prev == .Open or prev == .Punct do
        return .Ord
    if !hasNext or next == .Rel or next == .Close or next == .Punct do
        return .Ord
    return cls
}

// TeX atom spacing, expressed in mu (1/18 em). The compact table preserves the
// important distinctions: binary operators, relations, named operators and inner
// formulae. Open/close punctuation intentionally suppresses most spacing.
private func mathSpacingMu(left, right: MathAtomClass)->f32
{
    if left == .Punct do
        return 3
    if right == .Punct or right == .Close do
        return 0
    if left == .Open do
        return 0

    if left == .Rel or right == .Rel do
        return 5
    if left == .Bin or right == .Bin do
        return 4
    if left == .Op or right == .Op do
        return 3
    if left == .Inner or right == .Inner do
        return 3
    return 0
}

private func mathPrepareNode(node: *MathNode, style: MathStyle)
{
    node.style = style
    node.metrics.width, node.metrics.ascent, node.metrics.descent = 0
    node.offsets.clear()
    node.offsets.resize(node.children.count)
    node.rules.clear()
    node.draws.clear()
    node.paths.clear()
}

private func mathAddText(node: *MathNode, text: string, font: *Font, scale, x, baseline: f32)
{
    node.draws.add({text: text, pos: {x, baseline}, font: font, scale: scale})
}

private func mathLayoutSymbol(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    var scale = mathStyleScale(style, options)
    if node.flag
    {
        if style == .Display do
            scale *= 1.35
        elif style == .Text do
            scale *= 1.15
    }

    let drawFont = mathResolveFont(font, variant, node.text.toString())
    let measured = Painter.measureString(node.text.toString(), drawFont)

    node.metrics.width   = measured.width * scale
    node.metrics.ascent  = Math.max(0.0'f32, measured.ascent * scale)
    node.metrics.descent = Math.max(0.0'f32, measured.descent * scale)
    mathAddText(node, node.text.toString(), drawFont, scale, 0, 0)
}

private func mathLayoutRow(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    let em            = cast(f32) font.size * mathStyleScale(style, options)
    var x             = 0.0'f32
    var previousClass = MathAtomClass.Ord
    var hasPrevious   = false

    for child, idx in node.children
    {
        mathLayoutNode(child, font, style, variant, options)

        if child.kind != .Space
        {
            let cls = mathNormalizedClass(node, idx)
            if hasPrevious do
                x += mathSpacingMu(previousClass, cls) / 18.0 * em
            previousClass = cls
            hasPrevious   = true
        }

        node.offsets[idx]    = {x, 0}
        x                    += child.metrics.width
        node.metrics.ascent  = Math.max(node.metrics.ascent, child.metrics.ascent)
        node.metrics.descent = Math.max(node.metrics.descent, child.metrics.descent)
    }

    node.metrics.width = x
    if node.children.count
    {
        node.atomClass = node.children[0].atomClass
        if node.children.count > 1 do
            node.atomClass = .Inner
    }
}

private func mathLayoutFraction(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    let childStyle = mathCrampedStyle(style)
    let scale      = mathStyleScale(style, options)
    let em         = cast(f32) font.size * scale
    let rule       = node.flag ? mathRuleThickness(font, options, scale) : 0.0'f32
    let gap        = (node.flag ? 0.19'f32 : 0.13'f32) * em
    let pad        = 0.12'f32 * em
    let axisY      = -0.25'f32 * em

    let numerator   = node.children[0]
    let denominator = node.children[1]
    mathLayoutNode(numerator, font, childStyle, variant, options)
    mathLayoutNode(denominator, font, childStyle, variant, options)

    node.metrics.width = Math.max(numerator.metrics.width, denominator.metrics.width) + pad * 2
    let numeratorY   = axisY - rule * 0.5 - gap - numerator.metrics.descent
    let denominatorY = axisY + rule * 0.5 + gap + denominator.metrics.ascent
    node.offsets[0] = {(node.metrics.width - numerator.metrics.width) * 0.5, numeratorY}
    node.offsets[1] = {(node.metrics.width - denominator.metrics.width) * 0.5, denominatorY}

    node.metrics.ascent  = Math.max(-axisY + rule * 0.5, -(numeratorY - numerator.metrics.ascent))
    node.metrics.descent = Math.max(axisY + rule * 0.5, denominatorY + denominator.metrics.descent)
    if node.flag
    {
        let y = axisY
        node.rules.add({start: {0, y}, end: {node.metrics.width, y}, width: rule})
    }
}

private func mathLayoutRadical(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    let scale = mathStyleScale(style, options)
    let em    = cast(f32) font.size * scale
    let rule  = mathRuleThickness(font, options, scale)
    let gap   = 0.10'f32 * em

    let radicand = node.children[0]
    mathLayoutNode(radicand, font, style, variant, options)

    var contentX = 0.46'f32 * em
    var index: #null *MathNode
    if node.flag
    {
        index = node.children[1]
        mathLayoutNode(index!, font, .ScriptScript, variant, options)
        contentX = Math.max(contentX, index!.metrics.width * 0.72 + 0.08 * em)
    }

    let rootTop    = -radicand.metrics.ascent - gap - rule * 0.5
    let rootBottom = Math.max(radicand.metrics.descent, 0.18 * em)
    node.offsets[0]    = {contentX, 0}
    node.metrics.width = contentX + radicand.metrics.width + 0.06 * em
    node.paths.add(MathDrawPath{
        kind: MathPathKind.Radical,
        rect: {0, rootTop, node.metrics.width, rootBottom - rootTop},
        lineWidth: rule,
        aux: contentX})

    node.metrics.ascent  = Math.max(radicand.metrics.ascent + gap + rule, -rootTop + rule * 0.5)
    node.metrics.descent = Math.max(radicand.metrics.descent, rootBottom + rule * 0.5)

    if index
    {
        let value  = index!
        let target = rootBottom - rootTop
        let indexY = rootTop + value.metrics.ascent + 0.16 * target
        node.offsets[1]     = {0, indexY}
        node.metrics.ascent = Math.max(node.metrics.ascent, -(indexY - value.metrics.ascent))
    }
}

private func mathLayoutScripts(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    let base = node.children[0]
    mathLayoutNode(base, font, style, variant, options)

    let scriptStyle = mathNextStyle(style)
    var childIndex  = 1'u64
    var sub, sup:           #null *MathNode
    var subIndex, supIndex: u64
    if node.flag
    {
        sub        = node.children[childIndex]
        subIndex   = childIndex
        childIndex += 1
        mathLayoutNode(sub!, font, scriptStyle, variant, options)
    }

    if node.flag2
    {
        sup      = node.children[childIndex]
        supIndex = childIndex
        mathLayoutNode(sup!, font, scriptStyle, variant, options)
    }

    let scale      = mathStyleScale(style, options)
    let em         = cast(f32) font.size * scale
    var limitsMode = node.limitsMode
    if limitsMode == .Automatic do
        limitsMode = base.limitsMode
    let useLimits = base.atomClass == .Op and limitsMode != .NoLimits and (limitsMode == .Limits or style == .Display)

    if useLimits
    {
        let gap = 0.14'f32 * em
        node.metrics.width = base.metrics.width
        if sub do
            node.metrics.width = Math.max(node.metrics.width, sub!.metrics.width)
        if sup do
            node.metrics.width = Math.max(node.metrics.width, sup!.metrics.width)

        node.offsets[0]      = {(node.metrics.width - base.metrics.width) * 0.5, 0}
        node.metrics.ascent  = base.metrics.ascent
        node.metrics.descent = base.metrics.descent

        if sup
        {
            let value     = sup!
            let baselineY = -base.metrics.ascent - gap - value.metrics.descent
            node.offsets[supIndex] = {(node.metrics.width - value.metrics.width) * 0.5, baselineY}
            node.metrics.ascent    = Math.max(node.metrics.ascent, -(baselineY - value.metrics.ascent))
        }

        if sub
        {
            let value     = sub!
            let baselineY = base.metrics.descent + gap + value.metrics.ascent
            node.offsets[subIndex] = {(node.metrics.width - value.metrics.width) * 0.5, baselineY}
            node.metrics.descent   = Math.max(node.metrics.descent, baselineY + value.metrics.descent)
        }
    }
    else
    {
        let scriptX = base.metrics.width + 0.05 * em
        var supY    = 0.0'f32
        var subY    = 0.0'f32

        if sup
        {
            let value = sup!
            supY = -Math.max(0.48 * em, base.metrics.ascent * 0.72) + value.metrics.descent
        }

        if sub
        {
            let value = sub!
            subY = Math.max(0.24 * em, base.metrics.descent + 0.10 * em) + value.metrics.ascent
        }

        if sub and sup
        {
            let upperBottom = supY + sup!.metrics.descent
            let lowerTop    = subY - sub!.metrics.ascent
            let wantedGap   = 0.16 * em
            if lowerTop - upperBottom < wantedGap
            {
                let shift = (wantedGap - (lowerTop - upperBottom)) * 0.5
                supY -= shift
                subY += shift
            }
        }

        node.offsets[0]      = {0, 0}
        node.metrics.width   = base.metrics.width
        node.metrics.ascent  = base.metrics.ascent
        node.metrics.descent = base.metrics.descent
        if sup
        {
            let value = sup!
            node.offsets[supIndex] = {scriptX, supY}
            node.metrics.width     = Math.max(node.metrics.width, scriptX + value.metrics.width)
            node.metrics.ascent    = Math.max(node.metrics.ascent, -(supY - value.metrics.ascent))
        }

        if sub
        {
            let value = sub!
            node.offsets[subIndex] = {scriptX, subY}
            node.metrics.width     = Math.max(node.metrics.width, scriptX + value.metrics.width)
            node.metrics.descent   = Math.max(node.metrics.descent, subY + value.metrics.descent)
        }
    }

    node.atomClass = base.atomClass
}

private struct MathDelimiterMeasure
{
    width:    f32
    height:   f32
    scale:    f32
    kind:     MathPathKind
    usesPath: bool
}

private func mathDelimiterPathKind(text: string)->{ kind: MathPathKind, found: bool }
{
    if text == "(" do
        return {kind: .LeftParenthesis, found: true}
    if text == ")" do
        return {kind: .RightParenthesis, found: true}
    if text == "[" do
        return {kind: .LeftBracket, found: true}
    if text == "]" do
        return {kind: .RightBracket, found: true}
    if text == "{" do
        return {kind: .LeftBrace, found: true}
    if text == "}" do
        return {kind: .RightBrace, found: true}
    if text == "\u27E8" do
        return {kind: .LeftAngle, found: true}
    if text == "\u27E9" do
        return {kind: .RightAngle, found: true}
    if text == "\u230A" do
        return {kind: .LeftFloor, found: true}
    if text == "\u230B" do
        return {kind: .RightFloor, found: true}
    if text == "\u2308" do
        return {kind: .LeftCeiling, found: true}
    if text == "\u2309" do
        return {kind: .RightCeiling, found: true}
    if text == "|" do
        return {kind: .Bar, found: true}
    if text == "\u2016" do
        return {kind: .DoubleBar, found: true}
    return {}
}

private func mathMeasureDelimiter(text: string, font: *Font, minScale, targetHeight, em: f32)->MathDelimiterMeasure
{
    var result: retval
    if text == "." do
        return result

    let path = mathDelimiterPathKind(text)
    if path.found
    {
        result.kind     = path.kind
        result.usesPath = true
        result.height   = targetHeight
        switch path.kind
        {
        case .LeftParenthesis, .RightParenthesis: result.width = Math.clamp(targetHeight * 0.15, 0.28 * em, 0.50 * em)
        case .LeftBrace, .RightBrace:             result.width = Math.clamp(targetHeight * 0.20, 0.38 * em, 0.68 * em)
        case .LeftAngle, .RightAngle:             result.width = Math.clamp(targetHeight * 0.16, 0.30 * em, 0.52 * em)
        case .Bar:                                result.width = 0.14 * em
        case .DoubleBar:                          result.width = 0.30 * em
        default:                                  result.width = 0.30 * em
        }

        return result
    }

    let measured = Painter.measureString(text, font)
    result.scale = minScale
    if measured.height > 0 do
        result.scale = Math.max(result.scale, targetHeight / measured.height)
    result.width  = measured.width * result.scale
    result.height = measured.height * result.scale
    return result
}

private func mathLayoutDelimited(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    let body = node.children[0]
    mathLayoutNode(body, font, style, variant, options)

    let scale         = mathStyleScale(style, options)
    let em            = cast(f32) font.size * scale
    let targetHeight  = Math.max(em, body.metrics.height() + 0.16 * em)
    let delimiterFont = mathResolveFont(font, .Roman, "")
    let left          = mathMeasureDelimiter(node.text.toString(), delimiterFont, scale, targetHeight, em)
    let right         = mathMeasureDelimiter(node.text2.toString(), delimiterFont, scale, targetHeight, em)
    let pad           = 0.08'f32 * em
    let axisY         = -0.25'f32 * em
    let rule          = mathRuleThickness(font, options, scale)

    var x = 0.0'f32
    if node.text.toString() != "."
    {
        let top = axisY - left.height * 0.5
        if left.usesPath do
            node.paths.add(MathDrawPath{kind: left.kind, rect: {0, top, left.width, left.height}, lineWidth: rule})
        else
        {
            let measured = Painter.measureString(node.text.toString(), delimiterFont)
            mathAddText(node, node.text.toString(), delimiterFont, left.scale, 0, top + measured.ascent * left.scale)
        }

        x += left.width + pad
    }

    node.offsets[0] = {x, 0}
    x               += body.metrics.width

    if node.text2.toString() != "."
    {
        x += pad
        let top = axisY - right.height * 0.5
        if right.usesPath do
            node.paths.add(MathDrawPath{kind: right.kind, rect: {x, top, right.width, right.height}, lineWidth: rule})
        else
        {
            let measured = Painter.measureString(node.text2.toString(), delimiterFont)
            mathAddText(node, node.text2.toString(), delimiterFont, right.scale, x, top + measured.ascent * right.scale)
        }

        x += right.width
    }

    node.metrics.width   = x
    node.metrics.ascent  = body.metrics.ascent
    node.metrics.descent = body.metrics.descent
    if node.text.toString() != "."
    {
        let top = axisY - left.height * 0.5
        node.metrics.ascent  = Math.max(node.metrics.ascent, -top)
        node.metrics.descent = Math.max(node.metrics.descent, top + left.height)
    }

    if node.text2.toString() != "."
    {
        let top = axisY - right.height * 0.5
        node.metrics.ascent  = Math.max(node.metrics.ascent, -top)
        node.metrics.descent = Math.max(node.metrics.descent, top + right.height)
    }
}

private func mathLayoutAccent(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    let base = node.children[0]
    mathLayoutNode(base, font, style, variant, options)

    let scale = mathStyleScale(style, options)
    let em    = cast(f32) font.size * scale
    let gap   = 0.06'f32 * em
    let rule  = mathRuleThickness(font, options, scale)

    var accentWidth = base.metrics.width
    let accentText  = node.text.toString()
    if accentText == "^" or accentText == "~" do
        accentWidth = Math.max(accentWidth, 0.55 * em)
    elif accentText == "\u2192" do
        accentWidth = Math.max(accentWidth, 0.72 * em)

    node.offsets[0]    = {(accentWidth - base.metrics.width) * 0.5, 0}
    node.metrics       = base.metrics
    node.metrics.width = accentWidth

    if node.flag2
    {
        let y = node.flag ? base.metrics.descent + gap : -base.metrics.ascent - gap
        node.rules.add({start: {0, y}, end: {accentWidth, y}, width: rule})
        if node.flag do
            node.metrics.descent = Math.max(node.metrics.descent, y + rule * 0.5)
        else do
            node.metrics.ascent = Math.max(node.metrics.ascent, -y + rule * 0.5)
        return
    }

    if accentText == "\u00AF"
    {
        let y = -base.metrics.ascent - gap
        node.rules.add({start: {0, y}, end: {accentWidth, y}, width: rule})
        node.metrics.ascent = Math.max(node.metrics.ascent, -y + rule * 0.5)
        return
    }

    var pathKind   = MathPathKind.Hat
    var pathHeight = 0.0'f32
    var usesPath: bool
    if accentText == "^"
    {
        pathKind   = .Hat
        pathHeight = 0.18 * em
        usesPath   = true
    }
    elif accentText == "~"
    {
        pathKind   = .Tilde
        pathHeight = 0.13 * em
        usesPath   = true
    }
    elif accentText == "\u2192"
    {
        pathKind   = .Vector
        pathHeight = 0.18 * em
        usesPath   = true
    }

    if usesPath
    {
        let bottom = -base.metrics.ascent - gap
        let top    = bottom - pathHeight
        node.paths.add(MathDrawPath{kind: pathKind, rect: {0, top, accentWidth, pathHeight}, lineWidth: rule})
        node.metrics.ascent = Math.max(node.metrics.ascent, -top + rule * 0.5)
        return
    }

    let accentFont = mathResolveFont(font, .Roman, node.text.toString())
    let measured   = Painter.measureString(node.text.toString(), accentFont)
    let drawnWidth = measured.width * scale
    if drawnWidth > node.metrics.width
    {
        node.metrics.width = drawnWidth
        node.offsets[0].x  = (drawnWidth - base.metrics.width) * 0.5
    }

    let accentX = (node.metrics.width - drawnWidth) * 0.5
    if node.flag
    {
        let baseline = base.metrics.descent + gap + measured.ascent * scale
        mathAddText(node, node.text.toString(), accentFont, scale, accentX, baseline)
        node.metrics.descent = Math.max(node.metrics.descent, baseline + measured.descent * scale)
    }
    else
    {
        let baseline = -base.metrics.ascent - gap - measured.descent * scale
        mathAddText(node, node.text.toString(), accentFont, scale, accentX, baseline)
        node.metrics.ascent = Math.max(node.metrics.ascent, -(baseline - measured.ascent * scale))
    }
}

private func mathLayoutMatrix(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    var cellStyle = style
    if style == .Display do
        cellStyle = .Text

    var columnCount = 0'u32
    for count in node.rowLengths do
        columnCount = Math.max(columnCount, count)

    var columnWidths: Array'f32
    var rowAscents:   Array'f32
    var rowDescents:  Array'f32
    columnWidths.resize(columnCount)
    rowAscents.resize(node.rowLengths.count)
    rowDescents.resize(node.rowLengths.count)

    var childIndex = 0'u64
    for count, row in node.rowLengths
    {
        for column in count
        {
            let child = node.children[childIndex]
            mathLayoutNode(child, font, cellStyle, variant, options)
            columnWidths[column] = Math.max(columnWidths[column], child.metrics.width)
            rowAscents[row]      = Math.max(rowAscents[row], child.metrics.ascent)
            rowDescents[row]     = Math.max(rowDescents[row], child.metrics.descent)
            childIndex           += 1
        }
    }

    let scale     = mathStyleScale(style, options)
    let em        = cast(f32) font.size * scale
    let columnGap = options.columnGapEm * em
    let rowGap    = options.rowGapEm * em
    var totalWidth, totalHeight: f32
    for width, idx in columnWidths
    {
        totalWidth += width
        if idx + 1 < columnWidths.count do
            totalWidth += columnGap
    }

    for ascent, idx in rowAscents
    {
        totalHeight += ascent + rowDescents[idx]
        if idx + 1 < rowAscents.count do
            totalHeight += rowGap
    }

    let axisY = -0.25'f32 * em
    var y     = axisY - totalHeight * 0.5
    childIndex = 0
    for count, row in node.rowLengths
    {
        let baseline = y + rowAscents[row]
        var x        = 0.0'f32
        for column in count
        {
            let child = node.children[childIndex]
            node.offsets[childIndex] = {x + (columnWidths[column] - child.metrics.width) * 0.5, baseline}
            x                        += columnWidths[column] + columnGap
            childIndex               += 1
        }

        y += rowAscents[row] + rowDescents[row] + rowGap
    }

    node.metrics.width   = totalWidth
    node.metrics.ascent  = -(axisY - totalHeight * 0.5)
    node.metrics.descent = axisY + totalHeight * 0.5
}

private func mathLayoutNode(node: *MathNode, font: *Font, style: MathStyle, variant: MathFontVariant, options: const &MathLayoutOptions)
{
    mathPrepareNode(node, style)

    switch node.kind
    {
    case .Symbol:
        mathLayoutSymbol(node, font, style, variant, options)

    case .Space:
        node.metrics.width = node.spaceEm * cast(f32) font.size * mathStyleScale(style, options)

    case .Row:
        mathLayoutRow(node, font, style, variant, options)

    case .Fraction:
        mathLayoutFraction(node, font, style, variant, options)

    case .Radical:
        mathLayoutRadical(node, font, style, variant, options)

    case .Scripts:
        mathLayoutScripts(node, font, style, variant, options)

    case .Delimited:
        mathLayoutDelimited(node, font, style, variant, options)

    case .Accent:
        mathLayoutAccent(node, font, style, variant, options)

    case .Matrix:
        mathLayoutMatrix(node, font, style, variant, options)

    case .Style:
        let child = node.children[0]
        mathLayoutNode(child, font, style, node.fontVariant, options)
        node.offsets[0] = {0, 0}
        node.metrics    = child.metrics
        node.atomClass  = child.atomClass
    }
}

private func mathStrokePath(painter: *Painter, path: *LinePath, color: Color, lineWidth: f32, joinStyle = JoinStyle.Miter)
{
    var pen = Pen.createSolid(color, lineWidth)
    pen.begCapStyle    = .None
    pen.endCapStyle    = .None
    pen.joinStyle      = joinStyle
    pen.joinMiterLimit = 4
    painter.drawPath(path, pen)
}

private func mathDrawPath(painter: *Painter, draw: const &MathDrawPath, x, baseline: f32, color: Color)
{
    let l = x + draw.rect.x
    let t = baseline + draw.rect.y
    let r = l + draw.rect.width
    let b = t + draw.rect.height
    let w = draw.rect.width
    let h = draw.rect.height
    let m = (t + b) * 0.5

    var path:      LinePath
    var roundJoin: bool
    switch draw.kind
    {
    case .Radical:
        let shoulder = l + draw.aux - draw.lineWidth * 0.5
        path.start(l, t + h * 0.68)
        path.lineTo(l + draw.aux * 0.16, t + h * 0.60)
        path.lineTo(l + draw.aux * 0.38, b - draw.lineWidth * 0.5)
        path.lineTo(shoulder, t + draw.lineWidth * 0.5)
        path.lineTo(r, t + draw.lineWidth * 0.5)

    case .LeftParenthesis:
        path.start(r - draw.lineWidth * 0.5, t)
        path.bezierTo(l + draw.lineWidth * 0.5, m, l + w * 0.28, t + h * 0.10, l + w * 0.05, m - h * 0.24)
        path.bezierTo(r - draw.lineWidth * 0.5, b, l + w * 0.05, m + h * 0.24, l + w * 0.28, b - h * 0.10)
        roundJoin = true

    case .RightParenthesis:
        path.start(l + draw.lineWidth * 0.5, t)
        path.bezierTo(r - draw.lineWidth * 0.5, m, r - w * 0.28, t + h * 0.10, r - w * 0.05, m - h * 0.24)
        path.bezierTo(l + draw.lineWidth * 0.5, b, r - w * 0.05, m + h * 0.24, r - w * 0.28, b - h * 0.10)
        roundJoin = true

    case .LeftBracket:
        path.start(r, t + draw.lineWidth * 0.5)
        path.lineTo(l + draw.lineWidth * 0.5, t + draw.lineWidth * 0.5)
        path.lineTo(l + draw.lineWidth * 0.5, b - draw.lineWidth * 0.5)
        path.lineTo(r, b - draw.lineWidth * 0.5)

    case .RightBracket:
        path.start(l, t + draw.lineWidth * 0.5)
        path.lineTo(r - draw.lineWidth * 0.5, t + draw.lineWidth * 0.5)
        path.lineTo(r - draw.lineWidth * 0.5, b - draw.lineWidth * 0.5)
        path.lineTo(l, b - draw.lineWidth * 0.5)

    case .LeftBrace:
        let stem = l + w * 0.42
        path.start(r, t)
        path.bezierTo(stem, t + h * 0.20, l + w * 0.62, t, stem, t + h * 0.08)
        path.bezierTo(stem, m - h * 0.10, stem, t + h * 0.31, l + w * 0.62, m - h * 0.18)
        path.bezierTo(l, m, stem, m - h * 0.04, l + w * 0.10, m - h * 0.04)
        path.bezierTo(stem, m + h * 0.10, l + w * 0.10, m + h * 0.04, stem, m + h * 0.04)
        path.bezierTo(stem, b - h * 0.20, l + w * 0.62, m + h * 0.18, stem, b - h * 0.31)
        path.bezierTo(r, b, stem, b - h * 0.08, l + w * 0.62, b)
        roundJoin = true

    case .RightBrace:
        let stem = r - w * 0.42
        path.start(l, t)
        path.bezierTo(stem, t + h * 0.20, r - w * 0.62, t, stem, t + h * 0.08)
        path.bezierTo(stem, m - h * 0.10, stem, t + h * 0.31, r - w * 0.62, m - h * 0.18)
        path.bezierTo(r, m, stem, m - h * 0.04, r - w * 0.10, m - h * 0.04)
        path.bezierTo(stem, m + h * 0.10, r - w * 0.10, m + h * 0.04, stem, m + h * 0.04)
        path.bezierTo(stem, b - h * 0.20, r - w * 0.62, m + h * 0.18, stem, b - h * 0.31)
        path.bezierTo(l, b, stem, b - h * 0.08, r - w * 0.62, b)
        roundJoin = true

    case .LeftAngle:
        path.start(r, t)
        path.lineTo(l + draw.lineWidth * 0.5, m)
        path.lineTo(r, b)

    case .RightAngle:
        path.start(l, t)
        path.lineTo(r - draw.lineWidth * 0.5, m)
        path.lineTo(l, b)

    case .LeftFloor:
        path.start(l + draw.lineWidth * 0.5, t)
        path.lineTo(l + draw.lineWidth * 0.5, b - draw.lineWidth * 0.5)
        path.lineTo(r, b - draw.lineWidth * 0.5)

    case .RightFloor:
        path.start(r - draw.lineWidth * 0.5, t)
        path.lineTo(r - draw.lineWidth * 0.5, b - draw.lineWidth * 0.5)
        path.lineTo(l, b - draw.lineWidth * 0.5)

    case .LeftCeiling:
        path.start(r, t + draw.lineWidth * 0.5)
        path.lineTo(l + draw.lineWidth * 0.5, t + draw.lineWidth * 0.5)
        path.lineTo(l + draw.lineWidth * 0.5, b)

    case .RightCeiling:
        path.start(l, t + draw.lineWidth * 0.5)
        path.lineTo(r - draw.lineWidth * 0.5, t + draw.lineWidth * 0.5)
        path.lineTo(r - draw.lineWidth * 0.5, b)

    case .Bar:
        path.start((l + r) * 0.5, t)
        path.lineTo((l + r) * 0.5, b)

    case .DoubleBar:
        path.start(l + w * 0.30, t)
        path.lineTo(l + w * 0.30, b)
        mathStrokePath(painter, &path, color, draw.lineWidth)
        path.start(l + w * 0.70, t)
        path.lineTo(l + w * 0.70, b)

    case .Hat:
        path.start(l, b)
        path.lineTo((l + r) * 0.5, t + draw.lineWidth * 0.5)
        path.lineTo(r, b)

    case .Tilde:
        path.start(l, m)
        path.bezierTo((l + r) * 0.5, m, l + w * 0.18, t, l + w * 0.34, t)
        path.bezierTo(r, m, l + w * 0.66, b, l + w * 0.82, b)
        roundJoin = true

    case .Vector:
        let headWidth = Math.max(h * 0.72, draw.lineWidth * 2.5)
        let shaftHalf = Math.max(draw.lineWidth * 0.46, h * 0.11)
        path.start(l, m - shaftHalf)
        path.lineTo(r - headWidth, m - shaftHalf)
        path.lineTo(r - headWidth, t)
        path.lineTo(r, m)
        path.lineTo(r - headWidth, b)
        path.lineTo(r - headWidth, m + shaftHalf)
        path.lineTo(l, m + shaftHalf)
        path.close()
        painter.fillPath(&path, color)
        return
    }

    mathStrokePath(painter, &path, color, draw.lineWidth, roundJoin ? .Round : .Miter)
}

private func mathDrawNode(painter: *Painter, node: *MathNode, x, baseline: f32, color: Color)
{
    for path in node.paths do
        mathDrawPath(painter, path, x, baseline, color)

    for rule in node.rules
    {
        var pen = Pen.createSolid(color, rule.width)
        pen.begCapStyle = .None
        pen.endCapStyle = .None
        painter.drawLine(x + rule.start.x, baseline + rule.start.y, x + rule.end.x, baseline + rule.end.y, pen)
    }

    for draw in node.draws
    {
        let top = baseline + draw.pos.y - draw.font.ascent * draw.scale
        painter.drawString(x + draw.pos.x, top, draw.text, draw.font, color, .None, draw.scale)
    }

    for child, idx in node.children
    {
        let offset = node.offsets[idx]
        mathDrawNode(painter, child, x + offset.x, baseline + offset.y, color)
    }
}

public impl MathExpression
{
    // Measures the expression without drawing it.
    //
    // Repeated calls are allowed; the latest font, style, and options replace the
    // cached box metrics.
    mtd measure(font: *Font, options: MathLayoutOptions = {})->MathMetrics
    {
        Debug.assert(font != null, "math layout needs a font")
        mathLayoutNode(.root, font, options.style, .Default, options)
        return .root.metrics
    }
}

public impl Painter
{
    // Draw a parsed expression with its top-left at (left, top), returning the same
    // metrics as MathExpression.measure.
    #[Swag.Discardable]
    mtd drawMath(left, top: f32, expression: *MathExpression, font: *Font, color: Color, options: MathLayoutOptions = {})->MathMetrics
    {
        let metrics = expression.measure(font, options)
        if color.a != 0 do
            mathDrawNode(me, expression.root, left, top + metrics.ascent, color)
        return metrics
    }

    // Draw a parsed expression centered on (centerX, centerY).
    #[Swag.Discardable]
    mtd drawMathCenter(centerX, centerY: f32, expression: *MathExpression, font: *Font, color: Color, options: MathLayoutOptions = {})->MathMetrics
    {
        let metrics = expression.measure(font, options)
        if color.a != 0 do
            mathDrawNode(me, expression.root, centerX - metrics.width * 0.5, centerY - metrics.height() * 0.5 + metrics.ascent, color)
        return metrics
    }

    // Parse and draw a one-shot LaTeX expression. Cache MathExpression.parse when
    // the same formula is drawn every frame.
    #[Swag.Discardable]
    mtd drawMathLatex(left, top: f32, source: string, font: *Font, color: Color, options: MathLayoutOptions = {})->MathMetrics fail
    {
        var expression = MathExpression.parse(source)
        return .drawMath(left, top, &expression, font, color, options)
    }
}
