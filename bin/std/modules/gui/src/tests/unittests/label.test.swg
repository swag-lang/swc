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
    @assert(label.text() == "Hello")
    @assert(host.wndAt({40, 30}) == label)

    label.setText("World")
    @assert(label.text() == "World")

    label.setText(null)
    @assert(label.text() == "")
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

    @assert(label.flags.has(.WordWrap | .AutoHeight | .SecondaryText))
    @assert(label.textHorizontalAlignment == .Left and label.textVerticalAlignment == .Top)
    @assert(label.iconHorizontalAlignment == .Right and label.iconVerticalAlignment == .Bottom)
    @assert(label.textPadding == Math.Vector4{4, 3, 4, 3})
    @assert(label.iconPadding == Math.Vector4{2, 1, 2, 1})
    @assert(label.position.height >= 20)
}
