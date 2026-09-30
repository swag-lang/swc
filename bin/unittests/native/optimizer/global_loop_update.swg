#global private
using Swag

// A global updated inside a loop. Nothing promotes a global to a register, so
// its update is one read-modify-write on the cell itself, direct or indexed.
// A source pointer may name the very cell being updated: every read then has
// to see the write before it, which a cached copy of the global would not.

var g_Total:     u32
var g_Wide:      u64
var g_Hits:      u32
var g_Histogram: [16] u32
var g_Words:     [4] u32

#[Swag.Optimize(true), Swag.NoInline]
func addInto(values: const [*] u32, count: u64)
{
    for i in count do
        g_Total += values[i]
}

#[Swag.Optimize(true), Swag.NoInline]
func xorInto(values: const [*] u64, count: u64)
{
    for i in count do
        g_Wide ^= values[i]
}

#[Swag.Optimize(true), Swag.NoInline]
func countAbove(values: const [*] u32, count: u64, limit: u32)
{
    for i in count where values[i] > limit do
        g_Hits += 1
}

#[Swag.Optimize(true), Swag.NoInline]
func tally(values: const [*] u8, count: u64)
{
    for i in count do
        g_Histogram[values[i] & 15] += 1
}

// Four adjacent words updated in one trip: a packed group when the build
// vectorizes, four scalar updates otherwise.
#[Swag.Optimize(true), Swag.NoInline]
func addToWords(rounds: u64, step: u32)
{
    for rounds
    {
        g_Words[0] += step
        g_Words[1] += step
        g_Words[2] += step
        g_Words[3] += step
    }
}

#test
{
    var values: [4] u32 = [1, 2, 3, 4]
    g_Total = 5
    addInto(&values[0], 4)
    Swag.assert(g_Total == 15)

    // The source is the global: each trip doubles what the previous one wrote.
    g_Total = 3
    addInto(&g_Total, 1)
    Swag.assert(g_Total == 6)
    addInto(&g_Total, 1)
    Swag.assert(g_Total == 12)
}

#test
{
    var values: [3] u64 = [0xFF00, 0x0FF0, 0x00FF]
    g_Wide = 0
    xorInto(&values[0], 3)
    Swag.assert(g_Wide == 0xF00F)
    xorInto(&g_Wide, 1)
    Swag.assert(g_Wide == 0)
}

#test
{
    var values: [6] u32 = [1, 9, 3, 7, 5, 5]
    g_Hits = 0
    countAbove(&values[0], 6, 4)
    Swag.assert(g_Hits == 4)
    countAbove(&values[0], 0, 0)
    Swag.assert(g_Hits == 4)
}

#test
{
    var values: [6] u8 = [1, 17, 2, 33, 15, 2]
    tally(&values[0], 6)
    Swag.assert(g_Histogram[1] == 3 and g_Histogram[2] == 2 and g_Histogram[15] == 1 and g_Histogram[0] == 0)
}

#test
{
    g_Words = [1, 2, 3, 4]
    addToWords(3, 10)
    Swag.assert(g_Words[0] == 31 and g_Words[1] == 32 and g_Words[2] == 33 and g_Words[3] == 34)
    addToWords(0, 10)
    Swag.assert(g_Words[3] == 34)
}
