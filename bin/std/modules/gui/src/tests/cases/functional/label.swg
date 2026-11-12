#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

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
