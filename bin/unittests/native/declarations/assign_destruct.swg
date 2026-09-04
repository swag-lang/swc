#global private

struct Pair { a: s32; b: bool }

struct NativeAssignDestructRet
{
    first:  u32
    second: u32
}

func nativeMakeAnonymousAssignDestructRet(first, second: u32)->{ first, second: u32 }
{
    return {first, second}
}

func nativeMakeAssignDestructRet(first, second: u32)->NativeAssignDestructRet
{
    var result: retval
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
    Swag.assert(a == 0)
    Swag.assert(!b)
}

#test
{
    var s: Pair
    var a: s32
    {a, ?} = s
    Swag.assert(a == 0)
}

#test
{
    let pair = Pair{a: 81, b: true}
    let {b: second, a: first} = pair
    Swag.assert(first == 81)
    Swag.assert(second)

    var outA: s32
    var outB: bool
    {b: outB, a: outA} = pair
    Swag.assert(outA == 81)
    Swag.assert(outB)
}

#test
{
    var namedThenUnnamed = {x: 91's32, 92's32}
    var first:  s32
    var second: s32
    {item1: second, x: first} = namedThenUnnamed
    Swag.assert(first == 91)
    Swag.assert(second == 92)

    var unnamedThenNamed = {101's32, y: 102's32}
    {y: second, item0: first} = unnamedThenNamed
    Swag.assert(first == 101)
    Swag.assert(second == 102)
}

#test
{
    var first:  s32
    var second: s32
    {first, second} = {111, 112}
    Swag.assert(first == 111)
    Swag.assert(second == 112)

    {x: first, item1: second} = {x: 113, 114}
    Swag.assert(first == 113)
    Swag.assert(second == 114)

    {item0: first, y: second} = {115, y: 116}
    Swag.assert(first == 115)
    Swag.assert(second == 116)
}

#test
{
    var first:  u32
    var second: u32
    {first, second} = nativeMakeAssignDestructRet(11, 22)
    Swag.assert(first == 11)
    Swag.assert(second == 22)
}

#test
{
    var second: u32
    {?, second} = nativeMakeAssignDestructRet(33, 44)
    Swag.assert(second == 44)
}

#test
{
    var first:  u32 = 7
    var second: u32
    {first, second} = nativeMakeAssignDestructRet(first + 1, first + 2)
    Swag.assert(first == 8)
    Swag.assert(second == 9)
}

#test
{
    var first:  u32
    var second: u32
    {first, second} = nativeMakeAnonymousAssignDestructRet(55, 66)
    Swag.assert(first == 55)
    Swag.assert(second == 66)
}

#test
{
    var second: u32
    {?, second} = nativeMakeAnonymousAssignDestructRet(77, 88)
    Swag.assert(second == 88)
}

#test
{
    func run()->u32
    {
        func read(value: u32)->{ next, sum: u32 }
        {
            if value >= 3 do
                return {value + 1, value * 10}

            var next = value
            var sum: u32
            {next, sum} = read(value + 1)
            return {next, sum + value}
        }

        var total: u32
        {?, total} = read(1)
        return total
    }

    Swag.assert(run() == 33)
}

#test
{
    let data: [16] u32 = [2, 3, 0, 3, 10, 11, 12, 1, 1, 0, 1, 99, 2, 1, 1, 2]

    func read(n: const [..] u32, s: u32)->{ next, sum: u32 }
    {
        var start    = s
        let {nc, nm} = {n[start], n[start + 1]}
        start += 2

        if !nc
        {
            var sum: u32
            for i in nm do
                sum += n[start + i]
            return {start + nm, sum}
        }

        var childValues: [4] u32
        for i in nc
        {
            var sum: u32
            {start, sum}   = read(n, start)
            childValues[i] = sum
        }

        var sum: u32
        for i in nm
        {
            let idx = n[start + i]
            if idx and idx - 1 < nc do
                sum += childValues[idx - 1]
        }

        return {start + nm, sum}
    }

    let {nextLeaf, sumLeaf} = read(data[to], 2)
    Swag.assert(nextLeaf == 7)
    Swag.assert(sumLeaf == 33)

    let {nextBranch, sumBranch} = read(data[to], 7)
    Swag.assert(nextBranch == 13)
    Swag.assert(sumBranch == 0)

    var total: u32
    {?, total} = read(data[to], 0)
    Swag.assert(total == 66)
}
