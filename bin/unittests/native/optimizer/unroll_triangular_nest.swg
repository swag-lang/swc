#global private

// A pair loop, `for j in i + 1 until N` inside `for i in N`, has a constant number of pairs
// although the inner trip count changes with the outer counter. The optimizer unrolls the
// outer loop and then every inner loop, so each pair addresses its two elements directly.
// The results must match the loops as written, for the nests that flatten and for the ones
// that stay loops.

const N = 5

struct Cell
{
    value:  s64
    weight: s64
}

// Ten pairs over five cells: each pair exchanges a share of its weights.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func exchange(cells: [*] Cell)
{
    for i in N
    {
        let a = &cells[i]
        for j in i + 1 until N
        {
            let b     = &cells[j]
            let delta = (a.value - b.value) * (j - i)
            a.value -= delta * b.weight
            b.value += delta * a.weight
        }
    }
}

// The inner start does not follow the outer counter, so nothing fixes its trip count.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func exchangeFrom(cells: [*] Cell, first: s64)
{
    for i in N
    {
        let a = &cells[i]
        for j in first until N
        {
            let b = &cells[j]
            a.value += b.weight * (j + i)
        }
    }
}

// Sixteen elements make a hundred and twenty pairs: too much code, the nest stays.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func pairSum(values: [*] s64)->s64
{
    var total = 0's64
    for i in 16
    {
        for j in i + 1 until 16
        {
            values[i] += values[j] & 3
            total += values[i] * (j - i)
        }
    }

    return total
}

// A loop that runs exactly once keeps its body and nothing else.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func lastCell(cells: [*] Cell)->s64
{
    var total = 0's64
    for i in N - 1 until N do
        total += cells[i].value * cells[i].weight
    return total
}

func exchangeReference(cells: [*] Cell)
{
    var i = 0
    while i < N
    {
        var j = i + 1
        while j < N
        {
            let delta = (cells[i].value - cells[j].value) * (j - i)
            cells[i].value -= delta * cells[j].weight
            cells[j].value += delta * cells[i].weight
            j += 1
        }

        i += 1
    }
}

#test
{
    var cells:    [N] Cell = [{7, 1}, {-3, 2}, {11, -1}, {4, 3}, {-9, 2}]
    var expected: [N] Cell = [{7, 1}, {-3, 2}, {11, -1}, {4, 3}, {-9, 2}]
    exchange(&cells[0])
    exchangeReference(&expected[0])
    for i in N do
        Swag.assert(cells[i].value == expected[i].value and cells[i].weight == expected[i].weight)
    Swag.assert(cells[0].value == -3740 and cells[2].value == -82771 and cells[4].value == 127551)

    var plain: [N] Cell = [{1, 1}, {2, 2}, {3, 3}, {4, 4}, {5, 5}]
    exchangeFrom(&plain[0], 3)
    Swag.assert(plain[0].value == 33 and plain[1].value == 43 and plain[2].value == 53)
    Swag.assert(plain[3].value == 63 and plain[4].value == 73)

    var values: [16] s64
    for i in 16 do
        values[i] = i * 7 + 1
    let total = pairSum(&values[0])
    Swag.assert(total == 25596)
    Swag.assert(values[0] == 24 and values[14] == 101 and values[15] == 106)

    let last = lastCell(&plain[0])
    Swag.assert(last == 365)
}
