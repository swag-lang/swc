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
    let values = [Swag.U64.Max, 7_u64, 12_u64, 4_u64]
    Swag.require(guardedLastIndex(values) == 2)
}
