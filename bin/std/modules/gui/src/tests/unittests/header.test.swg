#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Header columns are added with a name and width.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 80)

    let header = Header.create(&host.root, {10, 10, 300, 24})
    @assert(header.items.count == 0)

    header.addColumn("Name", 120)
    header.addColumn("Size", 80)
    @assert(header.items.count == 2)

    @assert(header.itemAt(0).name.raw == "Name")
    @assert(header.itemAt(1).name.raw == "Size")
    @assert(Math.abs(header.itemWidthAt(0) - 120) < 0.01)
    @assert(header.itemForColumn(1) == header.itemAt(1))

    header.setItemWidthLimits(0, 100, 140)
    header.setItemWidth(0, 20)
    @assert(header.itemWidthAt(0) == 100)
    header.setItemWidthForColumn(0, 300)
    @assert(header.itemWidthAt(0) == 140)

    header.setSortIndicator(1, .Descending)
    @assert(header.sortColumn == 1 and header.sortDirection == .Descending)
    header.clearSortIndicator()
    @assert(header.sortColumn == Swag.U32.Max and header.sortDirection == .None)

    host.shutdown()
}
