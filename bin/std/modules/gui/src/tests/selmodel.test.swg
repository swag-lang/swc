#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var model: SelModel
    Swag.assert(model.isEmpty())
    Swag.assert(!model.isSelected(3))
    Swag.assert(model.rangeIndexContaining(3) == Swag.U32.Max)

    model.select(2)
    Swag.assert(!model.isEmpty())
    Swag.assert(model.isSelected(2))
    Swag.assert(model.rangeIndexContaining(2) == 0)
    Swag.assert(!model.isSelected(1))
    Swag.assert(!model.isSelected(3))
    Swag.assert(model.rangeCount() == 1)
    Swag.assert(model.selectedCount() == 1)
    Swag.assert(model.ranges()[0].start == 2)
    Swag.assert(model.ranges()[0].end == 2)

    model.selectRange(3, 5)
    Swag.assert(model.rangeCount() == 1)
    Swag.assert(model.ranges()[0].start == 2)
    Swag.assert(model.ranges()[0].end == 5)
    Swag.assert(model.selectedCount() == 4)

    model.unselect(4)
    Swag.assert(model.rangeCount() == 2)
    Swag.assert(model.ranges()[0].start == 2)
    Swag.assert(model.ranges()[0].end == 3)
    Swag.assert(model.ranges()[1].start == 5)
    Swag.assert(model.ranges()[1].end == 5)

    model.clear()
    Swag.assert(model.isEmpty())
}

#test
{
    var model: SelModel

    model.selectRange(8, 5)
    Swag.assert(model.ranges()[0].start == 5)
    Swag.assert(model.ranges()[0].end == 8)

    model.unselect(5)
    Swag.assert(model.ranges()[0].start == 6)
    Swag.assert(model.ranges()[0].end == 8)

    model.unselect(8)
    Swag.assert(model.ranges()[0].start == 6)
    Swag.assert(model.ranges()[0].end == 7)

    model.unselectRange(6, 7)
    Swag.assert(model.isEmpty())
}

#test
{
    var model: SelModel
    model.selectRange(1, 3)
    model.selectRange(6, 7)

    var visitedCount: u32
    var visitedSum:   u32
    for index in model
    {
        visitedCount += 1
        visitedSum   += index
    }

    Swag.assert(visitedCount == 5)
    Swag.assert(visitedSum == 19)
}

#test
{
    var model: SelModel

    model.unselect(10)
    Swag.assert(model.isEmpty())

    model.select(4)
    model.select(4)
    Swag.assert(model.rangeCount() == 1)
    Swag.assert(model.ranges()[0].start == 4)
    Swag.assert(model.ranges()[0].end == 4)

    model.selectRange(2, 6)
    Swag.assert(model.selectedCount() == 5)

    model.unselectRange(3, 5)
    Swag.assert(model.rangeCount() == 2)
    Swag.assert(model.ranges()[0].start == 2)
    Swag.assert(model.ranges()[0].end == 2)
    Swag.assert(model.ranges()[1].start == 6)
    Swag.assert(model.ranges()[1].end == 6)
}

#test
{
    var model: SelModel
    model.selectRange(1, 2)
    model.selectRange(4, 5)
    model.select(3)

    Swag.assert(model.rangeCount() == 1)
    Swag.assert(model.ranges()[0].start == 1)
    Swag.assert(model.ranges()[0].end == 5)

    var expected: u32 = 1
    for index in model
    {
        Swag.assert(index == expected)
        expected += 1
    }

    Swag.assert(expected == 6)
}

#test
{
    var model: SelModel
    model.selectRange(Swag.U32.Max, Swag.U32.Max - 2)
    model.select(Swag.U32.Max - 3)
    Swag.assert(model.rangeCount() == 1)
    Swag.assert(model.ranges()[0].start == Swag.U32.Max - 3)
    Swag.assert(model.ranges()[0].end == Swag.U32.Max)
    Swag.assert(model.selectedCount() == 4)

    model.unselectRange(Swag.U32.Max - 2, Swag.U32.Max - 1)
    Swag.assert(model.rangeCount() == 2)
    Swag.assert(model.ranges()[0].start == Swag.U32.Max - 3)
    Swag.assert(model.ranges()[0].end == Swag.U32.Max - 3)
    Swag.assert(model.ranges()[1].start == Swag.U32.Max)
    Swag.assert(model.ranges()[1].end == Swag.U32.Max)
}
