#global private

struct InlineBug10VisitBytes
{
    values: [5] u8
    count: u64
}

impl InlineBug10VisitBytes
{
    #[Macro]
    mtd(ptr: bool, back: bool) const opVisitBytes(stmt: #code void)
    {
        #if ptr do
            #error("visiting by pointer is not needed for this regression")

        for .count
        {
            #if back do
                let idx = .count - @index - 1
            #else do
                let idx = @index

            #macro
            {
                let #alias0 = #up me.values[#up idx]
                let #alias1 = #up idx
                #inject(#up stmt)
            }
        }
    }

    #[Macro, Swag.CalleeReturn]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code void)
    {
        .opVisitBytes'(ptr, back)(|#alias0, #alias1| stmt)
    }
}

#[Swag.Inline]
func inlineBug10ReverseIndexOfVisitAtLeast(values: const &InlineBug10VisitBytes, minValue: u8)->u64
{
    foreach #reverse value, index in values
    {
        if value < minValue do
            continue

        return index
    }

    return Swag.U64.Max
}

func bug10ReverseIndexOfVisitAtLeast(values: const &InlineBug10VisitBytes, minValue: u8)->u64
{
    foreach #reverse value, index in values
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
