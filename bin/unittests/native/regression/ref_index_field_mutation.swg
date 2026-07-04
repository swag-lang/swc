#global private

struct RefRange
{
    start: u32
    end:   u32
}

struct RefRangeStorage
{
    values: [2] RefRange
    count:  u32
}

impl RefRangeStorage
{
    mtd opIndex(index: u32)->&RefRange
    {
        return &.values[index]
    }

    mtd add(value: RefRange)
    {
        .values[.count] = value
        .count += 1
    }
}

struct RefRangeModel
{
    selection: RefRangeStorage
}

impl RefRangeModel
{
    mtd split(idx: u32)
    {
        let range: &RefRange = &.selection[0]
        #assert(#typeof(range) == #type &RefRange)
        let end   = range.end

        range.end = idx - 1
        .selection.add({idx + 1, end})
    }
}

#test
{
    var model: RefRangeModel
    model.selection.add({2, 6})

    model.split(4)

    @assert(model.selection.count == 2)
    @assert(model.selection.values[0].start == 2)
    @assert(model.selection.values[0].end == 3)
    @assert(model.selection.values[1].start == 5)
    @assert(model.selection.values[1].end == 6)
}
