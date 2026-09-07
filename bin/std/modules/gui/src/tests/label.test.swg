#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A label stores and returns its text, and is hit-testable.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)
    defer host.shutdown()
    let label = Label.create(&host.root, "Hello", {20, 20, 200, 20})
    Swag.assert(label.text() == "Hello")
    Swag.assert(host.wndAt({40, 30}) == label)

    label.setText("World")
    Swag.assert(label.text() == "World")

    label.setText(null)
    Swag.assert(label.text() == "")
}

// Presentation setters keep state coherent and automatic height reacts to layout changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 160)
    defer host.shutdown()
    let label = Label.create(&host.root, "A wrapped label that spans several words", {20, 20, 100, 20})
    label.updateFlags(.WordWrap | .AutoHeight | .SecondaryText)
    label.setTextAlignment(.Left, .Top)
    label.setIconAlignment(.Right, .Bottom)
    label.setTextPadding({4, 3, 4, 3})
    label.setIconPadding({2, 1, 2, 1})

    Swag.assert(label.flags.has(.WordWrap | .AutoHeight | .SecondaryText))
    Swag.assert(label.textHorizontalAlignment == .Left and label.textVerticalAlignment == .Top)
    Swag.assert(label.iconHorizontalAlignment == .Right and label.iconVerticalAlignment == .Bottom)
    Swag.assert(label.textPadding == Math.Vector4{4, 3, 4, 3})
    Swag.assert(label.iconPadding == Math.Vector4{2, 1, 2, 1})
    Swag.assert(label.position.height >= 20)
}

// Interline spacing changes the painted and measured text by the same amount.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 160)
    defer host.shutdown()
    let label = Label.create(&host.root, "First\nSecond\nThird", {0, 0, 200, 0}, flags: .WordWrap | .AutoHeight)
    label.setTextAlignment(.Left, .Top)
    let initial = label.measure({200, 0}).preferred.y
    label.setLineGap(4)
    Swag.assert(Math.abs(label.measure({200, 0}).preferred.y - initial - 8) < 0.5)
    var image = host.render(label)
    Swag.assert(Math.abs(label.name.boundRect.height - initial - 8) < 0.5)
    label.setLineGap(-1)
    Swag.assert(label.lineGap == 0)
    Swag.assert(Math.abs(label.measure({200, 0}).preferred.y - initial) < 0.5)
}
