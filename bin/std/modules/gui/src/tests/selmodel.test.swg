#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var model: SelModel
    @assert(model.isEmpty())
    @assert(!model.isSelected(3))
    @assert(model.getSelectedRangeIndex(3) == Swag.U32.Max)

    model.select(2, true)
    @assert(!model.isEmpty())
    @assert(model.isSelected(2))
    @assert(model.getSelectedRangeIndex(2) == 0)
    @assert(!model.isSelected(1))
    @assert(!model.isSelected(3))
    @assert(model.selection.count == 1)
    @assert(model.selection[0].start == 2)
    @assert(model.selection[0].end == 2)

    model.select(3, 5, true)
    @assert(model.selection.count == 1)
    @assert(model.selection[0].start == 2)
    @assert(model.selection[0].end == 5)
    @assert(model.isSelected(3))
    @assert(model.isSelected(4))
    @assert(model.isSelected(5))

    model.select(4, false)
    @assert(model.selection.count == 2)
    @assert(model.selection[0].start == 2)
    @assert(model.selection[0].end == 3)
    @assert(model.selection[1].start == 5)
    @assert(model.selection[1].end == 5)
    @assert(!model.isSelected(4))
    @assert(model.isSelected(5))

    model.unselectAll()
    @assert(model.isEmpty())
}

#test
{
    var model: SelModel

    model.select(8, 5, true)
    @assert(model.selection.count == 1)
    @assert(model.selection[0].start == 5)
    @assert(model.selection[0].end == 8)

    model.select(5, false)
    @assert(model.selection.count == 1)
    @assert(model.selection[0].start == 6)
    @assert(model.selection[0].end == 8)

    model.select(8, false)
    @assert(model.selection.count == 1)
    @assert(model.selection[0].start == 6)
    @assert(model.selection[0].end == 7)

    model.select(6, false)
    @assert(model.selection.count == 1)
    @assert(model.selection[0].start == 7)
    @assert(model.selection[0].end == 7)

    model.select(7, false)
    @assert(model.isEmpty())
}

#test
{
    var model: SelModel
    model.select(1, 3, true)
    model.select(6, 7, true)

    var visitedCount: u32
    var visitedSum:   u32
    foreach idx in model
    {
        visitedCount += 1
        visitedSum += idx
    }

    @assert(visitedCount == 5)
    @assert(visitedSum == 19)
}
