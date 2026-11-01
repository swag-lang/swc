#global private

#[Swag.NoInline]
func guardedLastIndex(values: const[..] u64)->u64
{
    var best, index: u64
    for value, i in values
    {
        if value != Swag.U64.Max and value >= best
        {
            best  = value
            index = i
        }
    }

    return index
}

#test
{
    let values = [Swag.U64.Max, 7'u64, 12'u64, 4'u64]
    Swag.assert(guardedLastIndex(values) == 2)
}
