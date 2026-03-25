#global fileprivate

// Advent of Code 2024 Day 7: determine which calibration equations can be
// satisfied by inserting operators, using heap-allocated equation storage
// and explicit cleanup through defer.

const InitialEquationCapacity = 4'u32
const MaxOperands = 16'u32

const SampleInput =
"""190: 10 19
3267: 81 40 27
83: 17 5
156: 15 6
7290: 6 8 6 15
161011: 16 10 13
192: 17 8 14
21037: 9 7 18 13
292: 11 6 16 20"""

const SingleInput = "6: 2 3\n"
const ConcatInput = "156: 15 6\n192: 17 8 14\n"

enum Operator: u8
{
    Add
    Mul
    Concat
}

struct Equation
{
    target:       u64
    operandCount: u32
    operands:     [MaxOperands] u64
}

struct EquationList
{
    data:      [*] Equation
    count:     u32
    capacity:  u32
    growCount: u32
}

struct CalibrationReport
{
    equationCount:    u32
    twoOpTotal:       u64
    threeOpTotal:     u64
    allocGrowCount:   u32
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func isDigit(ch: u8)->bool
{
    return ch >= '0' and ch <= '9'
}

func isLineBreak(ch: u8)->bool
{
    return ch == '\n''u8 or ch == '\r''u8
}

func concatNumbers(a, b: u64)->u64
{
    var magnitude = 1'u64
    var tmp = b
    for
    {
        magnitude *= 10
        tmp /= 10
        if tmp == 0 do
            break
    }

    return a * magnitude + b
}

// ---------------------------------------------------------------------------
// Heap-allocated equation list
// ---------------------------------------------------------------------------

func initEquationList(initialCapacity: u32)->EquationList
{
    var result: EquationList
    result.capacity = initialCapacity
    result.data = cast([*] Equation) @alloc(cast(u64) initialCapacity * cast(u64) #sizeof(Equation))
    @assert(result.data != null)
    return result
}

func freeEquationList(list: EquationList)
{
    if list.data do
        @free(list.data)
}

func appendEquation(list: EquationList, eq: Equation)->EquationList
{
    var result = list

    if result.count == result.capacity
    {
        let newCapacity = result.capacity * 2'u32
        result.data = cast([*] Equation) @realloc(result.data, cast(u64) newCapacity * cast(u64) #sizeof(Equation))
        @assert(result.data != null)
        result.capacity = newCapacity
        result.growCount += 1'u32
    }

    result.data[result.count] = eq
    result.count += 1'u32
    return result
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

func parseU64(bytes: const [..] u8, pos: *u32)->u64
{
    var value: u64
    while dref pos < @countof(bytes) and isDigit(bytes[dref pos])
    {
        value = value * 10 + cast(u64) (bytes[dref pos] - '0')
        dref pos += 1
    }

    return value
}

func skipSpaces(bytes: const [..] u8, pos: *u32)
{
    while dref pos < @countof(bytes) and bytes[dref pos] == ' ''u8
    {
        dref pos += 1
    }
}

func parseEquations(text: string)->EquationList
{
    let bytes = cast(const [..] u8) text
    var list = initEquationList(InitialEquationCapacity)
    var pos: u32

    while pos < @countof(bytes)
    {
        if isLineBreak(bytes[pos])
        {
            pos += 1
            continue
        }

        var eq: Equation
        eq.target = parseU64(bytes, &pos)

        @assert(pos < @countof(bytes) and bytes[pos] == ':''u8)
        pos += 1
        skipSpaces(bytes, &pos)

        while pos < @countof(bytes) and !isLineBreak(bytes[pos])
        {
            @assert(eq.operandCount < MaxOperands)
            eq.operands[eq.operandCount] = parseU64(bytes, &pos)
            eq.operandCount += 1
            skipSpaces(bytes, &pos)
        }

        list = appendEquation(list, eq)
    }

    return list
}

// ---------------------------------------------------------------------------
// Solver: recursive operator search
// ---------------------------------------------------------------------------

func canSolve(eq: Equation, accumulator: u64, index: u32, allowConcat: bool)->bool
{
    if index == eq.operandCount do
        return accumulator == eq.target
    if accumulator > eq.target do
        return false

    let next = eq.operands[index]
    let nextIndex = index + 1

    if canSolve(eq, accumulator + next, nextIndex, allowConcat) do
        return true
    if canSolve(eq, accumulator * next, nextIndex, allowConcat) do
        return true
    if allowConcat and canSolve(eq, concatNumbers(accumulator, next), nextIndex, allowConcat) do
        return true

    return false
}

func isEquationSolvable(eq: Equation, allowConcat: bool)->bool
{
    if eq.operandCount == 0 do
        return eq.target == 0
    return canSolve(eq, eq.operands[0], 1, allowConcat)
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

func calibrate(text: string)->CalibrationReport
{
    var list = parseEquations(text)
    defer freeEquationList(list)

    var result: CalibrationReport
    result.equationCount = list.count
    result.allocGrowCount = list.growCount

    for list.count
    {
        let eq = list.data[cast(u32) @index]

        if isEquationSolvable(eq, false) do
            result.twoOpTotal += eq.target
        if isEquationSolvable(eq, true) do
            result.threeOpTotal += eq.target
    }

    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    @assert(concatNumbers(15, 6) == 156)
    @assert(concatNumbers(1, 0) == 10)
    @assert(concatNumbers(0, 5) == 5)
    @assert(concatNumbers(12, 345) == 12345)
    @assert(concatNumbers(99, 99) == 9999)
}

#test
{
    let sample = calibrate(SampleInput)

    @assert(sample.equationCount == 9'u32)
    @assert(sample.twoOpTotal == 3749'u64)
    @assert(sample.threeOpTotal == 11387'u64)
    @assert(sample.allocGrowCount == 2'u32)
}

#test
{
    let single = calibrate(SingleInput)

    @assert(single.equationCount == 1'u32)
    @assert(single.twoOpTotal == 6'u64)
    @assert(single.threeOpTotal == 6'u64)
    @assert(single.allocGrowCount == 0'u32)
}

#test
{
    let concat = calibrate(ConcatInput)

    @assert(concat.equationCount == 2'u32)
    @assert(concat.twoOpTotal == 0'u64)
    @assert(concat.threeOpTotal == 348'u64)
}
