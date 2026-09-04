#global public
#global namespace Markdown

using Core, Pixel

internal struct MathView
{
    using wnd:  Wnd
    expression: MathExpression
    #[Swag.Late]
    owner: *View
}

internal impl MathView
{
    func create(owner: *View, parent: *Wnd, source: string)->#null *MathView
    {
        let expression = catch MathExpression.parse(source) as parseError
        if parseError != null do
            return null

        let result = Wnd.create'MathView(parent, "gui.markdown.math")
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

internal impl IWnd for MathView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect = .clientRect()
        evt.paintContext.painter.drawMathCenter(rect.horzCenter(), rect.vertCenter(), &.expression, .theme().createDefaultFont(.owner.documentStyle.mathFontSize), .themeColors().label_Text)
    }
}
