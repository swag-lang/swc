#global private
using Swag

// A local array cleared where it is declared and then written whole before
// any read loses its clear, even when its address is handed out afterwards.
// A partial overwrite, a read before the overwrite, and a read through a copy
// of the array's address must each still see the zeros.

#[Swag.NoInline]
func sum(values: const [*] u64, count: u64)->u64
{
    var total = 0'u64
    for i in count do
        total += values[i]
    return total
}

#[Swag.Optimize(true), Swag.NoInline]
func overwritten(a, b, c, d: u64)->u64
{
    var tile: [4] u64
    tile[0] = a
    tile[1] = b
    tile[2] = c
    tile[3] = d
    return sum(tile.buffer, 4)
}

#[Swag.Optimize(true), Swag.NoInline]
func partlyOverwritten(a, b, c: u64)->u64
{
    var tile: [4] u64
    tile[0] = a
    tile[1] = b
    tile[2] = c
    return sum(tile.buffer, 4) + tile[3] * 1000
}

#[Swag.Optimize(true), Swag.NoInline]
func readBeforeOverwrite(a, b, c, d: u64)->u64
{
    var tile: [4] u64
    let before = tile[2]
    tile[0] = a
    tile[1] = b
    tile[2] = c
    tile[3] = d
    return sum(tile.buffer, 4) + before * 1000
}

#[Swag.Optimize(true), Swag.NoInline]
func readThroughCopiedAddress(a, b, c, d: u64)->u64
{
    var tile: [4] u64
    let view   = tile.buffer
    let before = view[3]
    tile[0] = a
    tile[1] = b
    tile[2] = c
    tile[3] = d
    return sum(tile.buffer, 4) + before * 1000
}

#[Swag.Optimize(true), Swag.NoInline]
func overwrittenAfterGuard(enabled: bool, input: const *[4] u64)->u64
{
    if not enabled do
        return 0

    var tile: [4] u64
    tile[0] = input[][0]
    tile[1] = input[][1]
    tile[2] = input[][2]
    tile[3] = input[][3]
    return sum(tile.buffer, 4)
}

#test
{
    let input = [11'u64, 17, 23, 31]
    Swag.assert(overwrittenAfterGuard(true, &input) == 82)
    Swag.assert(overwrittenAfterGuard(false, &input) == 0)
    Swag.assert(overwritten(1, 2, 3, 4) == 10)
    Swag.assert(partlyOverwritten(1, 2, 3) == 6)
    Swag.assert(readBeforeOverwrite(1, 2, 3, 4) == 10)
    Swag.assert(readThroughCopiedAddress(1, 2, 3, 4) == 10)
}
