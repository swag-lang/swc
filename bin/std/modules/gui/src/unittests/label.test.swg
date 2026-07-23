#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A label stores and returns its text, and is hit-testable.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let label = Label.create(&host.root, "Hello", {20, 20, 200, 20})
    @assert(label.getText() == "Hello")
    @assert(host.wndAt({40, 30}) == label)

    label.setText("World")
    @assert(label.getText() == "World")

    label.setText(null)
    @assert(label.getText() == "")

    host.shutdown()
}
