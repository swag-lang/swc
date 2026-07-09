#global private

struct InlineBug10VisitBytes
{
    values: [5] u8
    count: u64
}

impl InlineBug10VisitBytes
{
    #[Macro]
    mtd(ptr: bool, back: bool) const opVisitBytes(stmt: #code(item: u8, index: u64))
    {
        #if ptr do
            #error("visiting by pointer is not needed for this regression")

        for .count
        {
            #if back do
                let idx = .count - @index - 1
            #else do
                let idx = @index

            #inject(stmt, item = me.values[idx], index = idx)
        }
    }

    #[Macro, Swag.CalleeReturn]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: u8, index: u64))
    {
        .opVisitBytes'(ptr, back)(stmt)
    }
}

#[Swag.Inline]
func inlineBug10ReverseIndexOfVisitAtLeast(values: const &InlineBug10VisitBytes, minValue: u8)->u64
{
    for #reverse value, index in values
    {
        if value < minValue do
            continue

        return index
    }

    return Swag.U64.Max
}

func bug10ReverseIndexOfVisitAtLeast(values: const &InlineBug10VisitBytes, minValue: u8)->u64
{
    for #reverse value, index in values
    {
        if value < minValue do
            continue

        return index
    }

    return Swag.U64.Max
}

#test
{
    var values = [1'u8, 4, 2, 9, 3]
    let visitValues = InlineBug10VisitBytes{values, @countof(values)}
    @assert(bug10ReverseIndexOfVisitAtLeast(visitValues, 8) == 3)
    @assert(inlineBug10ReverseIndexOfVisitAtLeast(visitValues, 8) == 3)
    @assert(inlineBug10ReverseIndexOfVisitAtLeast(visitValues, 10) == Swag.U64.Max)
}
