#global private

// Reusing the exchanged input must not read the previous value stored in memory.
#[Swag.NoInline]
func exchangeThenReuse(progress: *u32, column: u32)->u32
{
    Swag.atomxchg(progress, column + 1)
    return column + 1
}

// Publishing progress must preserve the next column used to recognize the final block.
#[Swag.NoInline]
func finalBlockCount(progress: *u32, row, rows, width: u32)->u32
{
    var count: u32
    for column in width
    {
        Swag.atomxchg(progress, column + 1)
        let finalBlock = row + 1 == rows and column + 1 == width
        if finalBlock do
            count += 1
    }
    return count
}

#test
{
    var progress: u32 = 13
    Swag.assert(exchangeThenReuse(&progress, 6) == 7)
    Swag.assert(progress == 7)
}

#test
{
    var progress: u32
    Swag.assert(finalBlockCount(&progress, 3, 4, 7) == 1)
    Swag.assert(progress == 7)
}