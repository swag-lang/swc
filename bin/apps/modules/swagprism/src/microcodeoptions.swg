#global internal

using Core, Gui

// Measures the option fields in one row when they fit, or two rows in a narrow column.
struct MicrocodeOptions
{
    using wnd:    Wnd
    stage:        *ComboBox?
    optimization: *ComboBox?
}

impl MicrocodeOptions
{
    const Gap = 8.0

    func create(parent: *Wnd)->*MicrocodeOptions
    {
        let result = Wnd.create'MicrocodeOptions(parent)
        result.backgroundStyle = .Transparent
        result.padding         = {0, 0, 0, 8}
        result.stage           = ComboBox.create(result, {}, "prism.stage")
        result.optimization    = ComboBox.create(result, {}, "prism.optimize")
        return result
    }

    mtd arrangeFields()
    {
        if !.stage or !.optimization do
            return
        let client    = .paddedClientRect()
        let stageSize = .stage!.measure({}).preferred
        let levelSize = .optimization!.measure({}).preferred
        if client.width >= stageSize.x + Gap + levelSize.x
        {
            .stage!.arrange({client.x, client.y, client.width - Gap - levelSize.x, stageSize.y})
            .optimization!.arrange({client.right() - levelSize.x, client.y, levelSize.x, levelSize.y})
        }
        else
        {
            .stage!.arrange({client.x, client.y, client.width, stageSize.y})
            .optimization!.arrange({client.x, client.y + stageSize.y + Gap, levelSize.x, levelSize.y})
        }
    }
}

impl IWnd for MicrocodeOptions
{
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        if !.stage or !.optimization do
            return {}
        let stageSize = .stage!.measure({}).preferred
        let levelSize = .optimization!.measure({}).preferred
        let width     = stageSize.x + MicrocodeOptions.Gap + levelSize.x + .padding.x + .padding.z
        if available.x >= width do
            return {width, Math.max(stageSize.y, levelSize.y) + .padding.y + .padding.w}
        return {Math.max(stageSize.x, levelSize.x) + .padding.x + .padding.z, stageSize.y + MicrocodeOptions.Gap + levelSize.y + .padding.y + .padding.w}
    }

    mtd impl onLayout() { .arrangeFields() }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .arrangeFields()
        .wnd.IWnd.onResizeEvent(evt)
    }
}
