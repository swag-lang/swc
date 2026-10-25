#global private
using Swag

struct Cell
{
    a, b: s64
    c:    s64
}

// A loop over the elements of a constant-length array counts down and tests at
// the top; the optimizer runs it as straight-line copies, each element addressed
// from the start of the array.
#[Swag.Optimize(true), Swag.NoInline]
func bumpCells(seed: s64)->s64
{
    var cells: [5] Cell
    for i in 5 do
        cells[i] = Cell{seed + i, seed * i, 0}

    for &cell in cells
    {
        cell.a += cell.b
        cell.c = cell.a * 3
    }

    var total = 0's64
    for cell in cells do
        total += cell.a * 7 + cell.c
    return total
}

// A `break` leaves through the exit as well: the loop stays a loop.
#[Swag.Optimize(true), Swag.NoInline]
func firstNegative(seed: s64)->s64
{
    var cells: [4] Cell
    for i in 4 do
        cells[i] = Cell{seed - i * 3, 0, 0}

    var found = -1's64
    for cell, i in cells
    {
        if cell.a < 0
        {
            found = i
            break
        }
    }

    return found
}

#test
{
    for seed in [-4's64, 0, 3, 11]
    {
        var expected = 0's64
        for i in 5
        {
            let a = seed + i + seed * i
            expected += a * 7 + a * 3
        }

        Swag.assert(bumpCells(seed) == expected)
    }

    Swag.assert(firstNegative(5) == 2)
    Swag.assert(firstNegative(-1) == 0)
    Swag.assert(firstNegative(100) == -1)
}
