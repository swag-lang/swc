#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A natural-height label reflows when its line limit changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 180)

    let row   = StackLayoutCtrl.create(&host.root, .Top, {0, 0, 300, 170})
    let label = Label.create(row, "First\nSecond\nThird\nFourth", {0, 0, 240, 0})
    label.preferredSize.y = 0
    label.invalidateLayout()
    host.pump()
    let originalHeight = label.itf.measureContent({label.position.width, 0}).y

    label.setMaxLines(2)
    host.pump()
    let measuredHeight = label.itf.measureContent({label.position.width, 0}).y
    let layoutHeight   = label.measure({}).preferred.y
    Swag.require(originalHeight != measuredHeight,
                 Format.toString("Label max-lines heights: original %, measured %", originalHeight, measuredHeight).toString())
    Swag.require(label.position.height == layoutHeight,
                 Format.toString("Label height after max-lines: measured %, committed %", layoutHeight, label.position.height).toString())
}

// A hand-placed AutoHeight label shrinks when its line limit changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 180)

    let row   = StackLayoutCtrl.create(&host.root, .Top, {0, 0, 300, 170})
    let label = Label.create(row, "First\nSecond\nThird\nFourth", {0, 0, 240, 0}, flags: .AutoHeight)
    host.pump()
    let originalHeight = label.position.height

    label.setMaxLines(2)
    host.pump()
    let needed = label.itf.measureContent({label.position.width, label.position.height}).y
    Swag.require(label.position.height < originalHeight, "Max-lines should shrink AutoHeight")
    Swag.require(needed <= label.position.height,
                 Format.toString("AutoHeight after max-lines: needed %, committed %", needed, label.position.height).toString())
}

// A natural-size label reflows when its text padding changes the measured width.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 80)

    let row   = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 600, 40})
    let label = Label.create(row, "A label whose measured width includes its text insets")
    host.pump()
    let originalWidth = label.itf.measureContent({}).x

    label.setTextPadding({12, 0, 12, 0})
    host.pump()
    let measuredWidth = label.itf.measureContent({}).x
    let layoutWidth   = label.measure({}).preferred.x
    Swag.require(originalWidth != measuredWidth,
                 Format.toString("Label text padding widths: original %, measured %", originalWidth, measuredWidth).toString())
    Swag.require(label.position.width == layoutWidth,
                 Format.toString("Label width after text padding: measured %, committed %", layoutWidth, label.position.width).toString())
}

// A hand-placed AutoHeight label includes changed text padding in its height.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 100)

    let label = Label.create(&host.root, "Text padding grows the label", {20, 20, 160, 0}, flags: .AutoHeight)
    host.pump()
    let originalHeight = label.position.height

    label.setTextPadding({0, 4, 0, 4})
    host.pump()
    let needed = label.itf.measureContent(Math.Point{label.position.width, label.position.height}).y
    Swag.require(label.position.height > originalHeight, "Text padding should increase AutoHeight")
    Swag.require(needed <= label.position.height,
                 Format.toString("AutoHeight after text padding: needed %, committed %", needed, label.position.height).toString())
}

// A natural-size label reflows when letter spacing changes its measured width.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 80)

    let row   = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 600, 40})
    let label = Label.create(row, "A label that grows when its letters are spaced farther apart")
    host.pump()
    let originalWidth = label.itf.measureContent({}).x

    label.setLetterSpacing(2)
    host.pump()
    let measuredWidth = label.itf.measureContent({}).x
    let layoutWidth   = label.measure({}).preferred.x
    Swag.require(originalWidth != measuredWidth,
                 Format.toString("Label letter spacing widths: original %, measured %", originalWidth, measuredWidth).toString())
    Swag.require(label.position.width == layoutWidth,
                 Format.toString("Label width after letter spacing: measured %, committed %", layoutWidth, label.position.width).toString())
}

// A hand-placed AutoHeight label keeps enough room after letter spacing changes its wrapped text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 400)

    let label = Label.create(&host.root, "A wrapped paragraph whose spaced letters need more room", {20, 20, 100, 0}, flags: .WordWrap | .AutoHeight)
    host.pump()
    label.setLetterSpacing(3)
    host.pump()

    let needed = label.itf.measureContent(Math.Point{label.position.width, label.position.height}).y
    Swag.require(needed <= label.position.height,
                 Format.toString("AutoHeight after letter spacing: needed %, committed %", needed, label.position.height).toString())
}

// A label stores and returns its text, and is hit-testable.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)
    let label = Label.create(&host.root, "Hello", {20, 20, 200, 20})
    Swag.require(label.text() == "Hello")
    Swag.require(host.wndAt({40, 30}) == label)

    label.setText("World")
    Swag.require(label.text() == "World")

    label.setText(null)
    Swag.require(label.text() == "")
}

// Presentation setters keep state coherent and automatic height reacts to layout changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 160)
    let label = Label.create(&host.root, "A wrapped label that spans several words", {20, 20, 100, 20})
    label.updateFlags(.WordWrap | .AutoHeight | .SecondaryText)
    label.setTextAlignment(.Left, .Top)
    label.setIconAlignment(.Right, .Bottom)
    label.setTextPadding({4, 3, 4, 3})
    label.setIconPadding({2, 1, 2, 1})

    Swag.require(label.flags.has(.WordWrap) and label.flags.has(.AutoHeight) and label.flags.has(.SecondaryText))
    Swag.require(label.textHorizontalAlignment == .Left and label.textVerticalAlignment == .Top)
    Swag.require(label.iconHorizontalAlignment == .Right and label.iconVerticalAlignment == .Bottom)
    Swag.require(label.textPadding == Math.Vector4{4, 3, 4, 3})
    Swag.require(label.iconPadding == Math.Vector4{2, 1, 2, 1})
    Swag.require(label.position.height >= 20)
}

// Interline spacing changes the painted and measured text by the same amount.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 160)
    let label = Label.create(&host.root, "First\nSecond\nThird", {0, 0, 200, 0}, flags: .WordWrap | .AutoHeight)
    label.setTextAlignment(.Left, .Top)
    let initial     = label.measure({200, 0}).preferred.y
    let initialText = label.name.boundRect.height
    label.setLineGap(4)
    Swag.require(Math.abs(label.measure({200, 0}).preferred.y - initial - 8) < 0.5)
    var image = host.render(label)
    Swag.require(Math.abs(label.name.boundRect.height - initialText - 8) < 0.5)
    label.setLineGap(-1)
    Swag.require(label.lineGap == 0)
    Swag.require(Math.abs(label.measure({200, 0}).preferred.y - initial) < 0.5)
}

// Automatic height includes the window padding that is removed before wrapped text is painted.
#test
{
    for scale in [1.0'f32, 1.25'f32, 1.5'f32, 1.75'f32, 2.0'f32]
    {
        var host: Testing.HeadlessHost
        host.setup(240, 400, scale)

        let label = Label.create(&host.root, "A wrapped paragraph whose final words need another line", {20, 20, 100, 0}, flags: .WordWrap | .AutoHeight)
        label.padding = {8, 4, 8, 4}
        label.setTextPadding({2, 2, 2, 2})

        var tail: String
        for index in 20
        {
            var text = String.from("A wrapped paragraph whose final words need another line")
            text += tail
            label.setText(text.toString())
            label.updateAutomaticHeight()

            let needed = label.itf.measureContent(Math.Point{label.position.width, label.position.height}).y
            Swag.require(needed <= label.position.height)
            tail += index % 2 == 0 ? "!" : "?"
        }
    }
}

// A hand-placed AutoHeight label grows when its icon needs more room than the caption.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 160)

    let label = Label.create(&host.root, "", {20, 20, 100, 0}, flags: .AutoHeight)
    label.setIcon(host.theme.icon(.Folder, 48))
    var needed = label.itf.measureContent(Math.Point{label.position.width, label.position.height}).y
    Swag.require(needed <= label.position.height)

    label.setIconPadding({1, 3, 1, 4})
    needed = label.itf.measureContent(Math.Point{label.position.width, label.position.height}).y
    Swag.require(needed <= label.position.height)
}
