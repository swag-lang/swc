#global fileprivate

// Advent of Code 2022 - Day 1: Calorie Counting
//
// Each Elf carries a list of food items (calories per item).
// Part 1: find the Elf with the most total calories.
// Part 2: find the total carried by the top 3 Elves.
//
// The solution deliberately exercises many Swag features:
// structs, enums, generics, lambdas, interfaces, UFCS,
// slices, foreach, compile-time assertions, and more.

const MaxElves = 8
const MaxFoodItemsPerElf = 8

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

enum Rank: u8
{
    First
    Second
    Third
}

struct FoodItem
{
    name:     string
    calories: u32
}

struct Elf
{
    id:       u32
    itemCount:u32
    items:    [MaxFoodItemsPerElf] FoodItem
}

// ---------------------------------------------------------------------------
// Interface: anything that can report a calorie total
// ---------------------------------------------------------------------------

interface ICalorieSource
{
    mtd totalCalories()->u32;
}

impl ICalorieSource for Elf
{
    func impl totalCalories(me)->u32
    {
        var total: u32
        foreach item in me.items[until me.itemCount] do
            total += item.calories
        return total
    }
}

// ---------------------------------------------------------------------------
// Generic utilities
// ---------------------------------------------------------------------------

func(T) maxOf(a, b: T)->T
{
    if a >= b do
        return a
    return b
}

func(T) minOf(a, b: T)->T
{
    if a <= b do
        return a
    return b
}

func(T) swap(a, b: *T)
{
    let tmp = dref a
    dref a = dref b
    dref b = tmp
}

// ---------------------------------------------------------------------------
// Core logic - written with UFCS style helpers
// ---------------------------------------------------------------------------

func elfTotal(elf: Elf)->u32
{
    let itf = cast(ICalorieSource) elf
    return itf.totalCalories()
}

func collectTotals(outTotals: [..] u32, elves: const [..] Elf, mapper: func(Elf)->u32)->u32
{
    @assert(@countof(outTotals) >= @countof(elves))

    let elfCount = cast(u32) @countof(elves)
    for elfCount
    {
        let index = cast(u32) @index
        outTotals[index] = mapper(elves[index])
    }

    return elfCount
}

func sortDescending(values: [..] u32)
{
    let count = @countof(values)
    for var i = 0'u64; i < count; i += 1
    {
        var best = i
        for var j = i + 1; j < count; j += 1
        {
            if values[j] > values[best] do
                best = j
        }

        if best != i do
            swap'(u32)(&values[i], &values[best])
    }
}

func solvePartOne(elves: const [..] Elf)->u32
{
    var best: u32
    foreach e in elves do
        best = maxOf'(u32)(best, elfTotal(e))
    return best
}

func(N: u32 = 3) solvePartTwo(elves: const [..] Elf)->u32
{
    var totals: [MaxElves] u32
    let totalCount = collectTotals(totals, elves, func(e: Elf)->u32 { return elfTotal(e) })
    sortDescending(totals[until totalCount])

    var sum: u32
    let limit = minOf'(u32)(N, totalCount)
    for var i = 0'u32; i < limit; i += 1 do
        sum += totals[i]
    return sum
}

// ---------------------------------------------------------------------------
// Rank helper - converts index to Rank enum.
// ---------------------------------------------------------------------------

func rankFromIndex(idx: u32)->Rank
{
    if idx == 0 do return Rank.First
    if idx == 1 do return Rank.Second
    return Rank.Third
}

// ---------------------------------------------------------------------------
// Builder helpers
// ---------------------------------------------------------------------------

func addFoodItem(elf: *Elf, name: string, calories: u32)
{
    @assert(elf.itemCount < MaxFoodItemsPerElf)
    let itemIndex = elf.itemCount
    elf.items[itemIndex] = FoodItem{name: name, calories: calories}
    elf.itemCount += 1
}

func makeElf(id: u32, cals: const [..] u32)->Elf
{
    var elf: Elf
    elf.id = id

    foreach c in cals do
        addFoodItem(&elf, "food", c)

    return elf
}

// ---------------------------------------------------------------------------
// Compile-time sanity checks
// ---------------------------------------------------------------------------

#assert(#sizeof(Rank) == 1)
#assert(#sizeof(FoodItem) != 0)

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    var elves: [5] Elf

    var e0: Elf
    e0.id = 0
    addFoodItem(&e0, "bread", 1000)
    addFoodItem(&e0, "cheese", 2000)
    addFoodItem(&e0, "apple", 3000)
    elves[0] = e0

    elves[1] = makeElf(1, [4000'u32])

    var e2: Elf
    e2.id = 2
    addFoodItem(&e2, "candy", 5000'u32)
    addFoodItem(&e2, "energy", 6000)
    elves[2] = e2

    elves[3] = makeElf(3, [7000'u32, 8000, 9000])
    elves[4] = makeElf(4, [10000'u32])

    let elfSlice = elves[ to ]
    @assert(@countof(elfSlice) == 5)

    let best = solvePartOne(elfSlice)
    @assert(best == 24000)

    let top3 = solvePartTwo(elfSlice)
    @assert(top3 == 45000)

    let top2 = solvePartTwo'(2)(elfSlice)
    @assert(top2 == 35000)

    let totalE0 = e0.ICalorieSource.totalCalories()
    @assert(totalE0 == 6000)

    @assert(maxOf'(u32)(10, 20) == 20)
    @assert(minOf'(u32)(10, 20) == 10)

    var a = 42'u32
    var b = 99'u32
    swap'(u32)(&a, &b)
    @assert(a == 99 and b == 42)

    @assert(rankFromIndex(0) == .First)
    @assert(rankFromIndex(1) == .Second)
    @assert(rankFromIndex(2) == .Third)

    var totals: [MaxElves] u32
    let totalCount = collectTotals(totals, elfSlice, func(e: Elf)->u32 { return elfTotal(e) })
    @assert(totalCount == 5)
    @assert(totals[0] == 6000)
    @assert(totals[3] == 24000)

    var sorted = totals
    sortDescending(sorted[until totalCount])
    @assert(sorted[0] == 24000)
    @assert(sorted[1] == 11000)
    @assert(sorted[2] == 10000)
    @assert(sorted[3] == 6000)
    @assert(sorted[4] == 4000)
}
