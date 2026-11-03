#global private

struct Pair { a: s32; b: bool }

struct NativeAssignDestructRet
{
    first:  u32
    second: u32
}

func nativeMakeAnonymousAssignDestructRet(first, second: u32)->{ first, second: u32 }
{
    return {first: first, second: second}
}

func nativeMakeAssignDestructRet(first, second: u32)->NativeAssignDestructRet
{
    var result: #returntype
    result.first  = first
    result.second = second
    return result
}

#test
{
    var s: Pair
    var a: s32
    var b: bool
    {a, b} = s
    Swag.require(a == 0)
    Swag.require(not b)
}

#test
{
    var s: Pair
    var a: s32
    {a, b: _} = s
    Swag.require(a == 0)
}

#test
{
    let pair = Pair{a: 81, b: true}
    let {b: second, a: first} = pair
    Swag.require(first == 81)
    Swag.require(second)

    var outA: s32
    var outB: bool
    {b: outB, a: outA} = pair
    Swag.require(outA == 81)
    Swag.require(outB)
}

#test
{
    var namedThenUnnamed = {x: 91's32, item1: 92's32}
    var first:  s32
    var second: s32
    {item1: second, x: first} = namedThenUnnamed
    Swag.require(first == 91)
    Swag.require(second == 92)

    var unnamedThenNamed = {item0: 101's32, y: 102's32}
    {y: second, item0: first} = unnamedThenNamed
    Swag.require(first == 101)
    Swag.require(second == 102)
}

#test
{
    var first:  s32
    var second: s32
    (first, second) = (111, 112)
    Swag.require(first == 111)
    Swag.require(second == 112)

    {x: first, item1: second} = {x: 113, item1: 114}
    Swag.require(first == 113)
    Swag.require(second == 114)

    {item0: first, y: second} = {item0: 115, y: 116}
    Swag.require(first == 115)
    Swag.require(second == 116)
}

#test
{
    var first:  u32
    var second: u32
    {first, second} = nativeMakeAssignDestructRet(11, 22)
    Swag.require(first == 11)
    Swag.require(second == 22)
}

#test
{
    var second: u32
    {first: _, second} = nativeMakeAssignDestructRet(33, 44)
    Swag.require(second == 44)
}

#test
{
    var first:  u32 = 7
    var second: u32
    {first, second} = nativeMakeAssignDestructRet(first + 1, first + 2)
    Swag.require(first == 8)
    Swag.require(second == 9)
}

#test
{
    var first:  u32
    var second: u32
    {first, second} = nativeMakeAnonymousAssignDestructRet(55, 66)
    Swag.require(first == 55)
    Swag.require(second == 66)
}

#test
{
    var second: u32
    {first: _, second} = nativeMakeAnonymousAssignDestructRet(77, 88)
    Swag.require(second == 88)
}

#test
{
    func run()->u32
    {
        func read(value: u32)->{ next, sum: u32 }
        {
            if value >= 3 do
                return {next: value + 1, sum: value * 10}

            var next = value
            var sum: u32
            {next, sum} = read(value + 1)
            return {next: next, sum: sum + value}
        }

        var total: u32
        {next: _, sum: total} = read(1)
        return total
    }

    Swag.require(run() == 33)
}

#test
{
    let data: [16] u32 = [2, 3, 0, 3, 10, 11, 12, 1, 1, 0, 1, 99, 2, 1, 1, 2]

    func read(n: const [..] u32, s: u32)->{ next, sum: u32 }
    {
        var start    = s
        let (nc, nm) = (n[start], n[start + 1])
        start += 2

        if not nc
        {
            var sum: u32
            for i in nm do
                sum += n[start + i]
            return {next: start + nm, sum: sum}
        }

        var childValues: [4] u32
        for i in nc
        {
            var sum: u32
            {next: start, sum} = read(n, start)
            childValues[i]     = sum
        }

        var sum: u32
        for i in nm
        {
            let idx = n[start + i]
            if idx and idx - 1 < nc do
                sum += childValues[idx - 1]
        }

        return {next: start + nm, sum: sum}
    }

    let {next: nextLeaf, sum: sumLeaf} = read(data[to], 2)
    Swag.require(nextLeaf == 7)
    Swag.require(sumLeaf == 33)

    let {next: nextBranch, sum: sumBranch} = read(data[to], 7)
    Swag.require(nextBranch == 13)
    Swag.require(sumBranch == 0)

    var total: u32
    {next: _, sum: total} = read(data[to], 0)
    Swag.require(total == 66)
}
