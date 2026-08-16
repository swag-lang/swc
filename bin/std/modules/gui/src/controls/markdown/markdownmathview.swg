#global public

using Core, Pixel

internal struct MarkdownMathView
{
    using wnd:  Wnd
    expression: MathExpression
    owner:      *MarkdownView = undefined
}

internal impl MarkdownMathView
{
    func create(owner: *MarkdownView, parent: *Wnd, source: string)->#null *MarkdownMathView
    {
        let expression = catch MathExpression.parse(source) as parseError
        if parseError != null do
            return null

        let result = Wnd.create'MarkdownMathView(parent, "gui.markdown.math")
        result.backgroundStyle = .View
        result.expression      = #move expression
        result.owner           = owner
        return result
    }

    mtd preferredHeight()->f32
    {
        let metrics = .expression.measure(.theme().createDefaultFont(.owner.documentStyle.mathFontSize))
        return Math.max(metrics.height() + 28, 64)
    }
}

internal impl IWnd for MarkdownMathView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect = .clientRect()
        evt.paintContext.painter.drawMathCenter(rect.horzCenter(), rect.vertCenter(), &.expression, .theme().createDefaultFont(.owner.documentStyle.mathFontSize), .themeColors().label_Text)
    }
}
