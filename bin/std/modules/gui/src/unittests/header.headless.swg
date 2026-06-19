#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

// Header columns are added with a name and width.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 80)

    let header = Header.create(&host.root, {10, 10, 300, 24})
    @assert(header.items.count == 0)

    header.addItem("Name", 120)
    header.addItem("Size", 80)
    @assert(header.items.count == 2)

    @assert(header.getItem(0).name.raw == "Name")
    @assert(header.getItem(1).name.raw == "Size")
    @assert(Math.abs(header.getItem(0).width - 120) < 0.01)
    @assert(header.getItem(1).column == 1)

    host.shutdown()
}
