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
