#global private

struct InlineBug10VisitBytes
{
    values: [5] u8
    count:  u64
}

impl InlineBug10VisitBytes
{
    mtd const reversed()->ConstReversedSlice'u8
    {
        return reverseSlice(@mkslice(&me.values[0], me.count))
    }

    #[Macro]
    mtd(ptr: bool) const visitBytes(stmt: #code(item: u8, index: u64))
        where !ptr
    {
        for .count
        {
            let idx = @index

            #inject(stmt, item = me.values[idx], index = idx)
        }
    }

    #[Macro, Swag.CalleeReturn]
    mtd(ptr: bool) const opVisit(stmt: #code(item: u8, index: u64))
    {
        .visitBytes'(ptr)(stmt)
    }
}

#[Swag.Inline]
func inlineBug10ReverseIndexOfVisitAtLeast(values: InlineBug10VisitBytes, minValue: u8)->u64
{
    for value, index in (values).reversed()
    {
        if value < minValue do
            continue

        return index
    }

    return Swag.U64.Max
}

func bug10ReverseIndexOfVisitAtLeast(values: InlineBug10VisitBytes, minValue: u8)->u64
{
    for value, index in (values).reversed()
    {
        if value < minValue do
            continue

        return index
    }

    return Swag.U64.Max
}

#test
{
    var values      = [1'u8, 4, 2, 9, 3]
    let visitValues = InlineBug10VisitBytes{values, @countof(values)}
    @assert(bug10ReverseIndexOfVisitAtLeast(visitValues, 8) == 3)
    @assert(inlineBug10ReverseIndexOfVisitAtLeast(visitValues, 8) == 3)
    @assert(inlineBug10ReverseIndexOfVisitAtLeast(visitValues, 10) == Swag.U64.Max)
}
