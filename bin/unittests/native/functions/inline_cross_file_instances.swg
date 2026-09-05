#global private

struct Cell
{
    value: s32
}

struct IndexedBuffers
{
    cells:   InlineCrossFile.Buffer'Cell
    numbers: InlineCrossFile.Buffer's32
}

impl IndexedBuffers
{
    mtd check()->s32
    {
        var index = 0'u32
        while index < 1
        {
            if .cells[.numbers[0 + index]].value != 42 do
                return 0
            index += 1
        }
        return 42
    }
}

#test
{
    Swag.assert(InlineCrossFile.Factory.create'Cell(20) == 23)
    Swag.assert(InlineCrossFile.Factory.create's32(20) == 23)
    var cells: [3] Cell
    var buffer = InlineCrossFile.Buffer'Cell{&cells[0]}
    buffer[1].value = 42
    Swag.assert(cells[1].value == 42)

    var values  = [1, 5, 7]
    var numbers = InlineCrossFile.Buffer's32{&values[0]}
    numbers[2] += buffer[numbers[0]].value
    Swag.assert(values[2] == 49)
    var indexed = IndexedBuffers{buffer, numbers}
    Swag.assert(indexed.check() == 42)

    var index = 0'u32
    while index < 1
    {
        Swag.assert(buffer[numbers[0 + index]].value == 42)
        index += 1
    }
}
