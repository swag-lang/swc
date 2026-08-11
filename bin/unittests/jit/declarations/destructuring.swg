#global private

struct DestructPair
{
    x: s32
    y: s32
}

struct JitAssignDestructRet
{
    first:  u32
    second: u32
}

func jitMakeAnonymousAssignDestructRet(first, second: u32)->{ first, second: u32 }
{
    return {first, second}
}

func jitMakeAssignDestructRet(first, second: u32)->JitAssignDestructRet
{
    var result: retval = undefined
    result.first  = first
    result.second = second
    return result
}

#test
{
    let pair   = DestructPair{x: 10, y: 20}
    let {a, b} = pair
    @assert(a == 10)
    @assert(b == 20)
}

#test
{
    var pair   = DestructPair{x: 10, y: 20}
    var {a, b} = pair
    @assert(a == 10)
    @assert(b == 20)
    a = 100
    b = 200
    @assert(a == 100)
    @assert(b == 200)
}

#test
{
    let {a, b} = {x: 1, y: 2}
    @assert(a == 1)
    @assert(b == 2)
}

#test
{
    var {a, b} = {x: 1, y: 2}
    @assert(a == 1)
    @assert(b == 2)
    a = 10
    b = 20
    @assert(a == 10)
    @assert(b == 20)
}

#test
{
    let {a, b, c} = {x: true, y: 42's32, z: 3.14}
    @assert(a == true)
    @assert(b == 42)
    @assert(c == 3.14)
}

#test
{
    var {a, b} = {x: true, y: false}
    @assert(a == true)
    @assert(b == false)
    a = false
    @assert(a == false)
}

#test
{
    let t      = {x: 1.0, y: 2.0, z: 3.0}
    let {a, ?} = {x: 10, y: 20}
    @assert(a == 10)
    let {?, b} = {x: 10, y: 20}
    @assert(b == 20)
}

#test
{
    let t         = {a: 1's32, b: 2's32, c: 3's32}
    let {?, ?, c} = t
    @assert(c == 3)
    let {x, ?, ?} = t
    @assert(x == 1)
    let {?, y, ?} = t
    @assert(y == 2)
}

#test
{
    let point                 = DestructPair{x: 10, y: 20}
    let {y: second, x: first} = point
    @assert(first == 10)
    @assert(second == 20)

    let {x: onlyX} = point
    @assert(onlyX == 10)
}

#test
{
    let namedThenUnnamed          = {x: 11's32, 22's32}
    let {item1: second, x: first} = namedThenUnnamed
    @assert(first == 11)
    @assert(second == 22)

    let unnamedThenNamed          = {33's32, y: 44's32}
    let {y: fourth, item0: third} = unnamedThenNamed
    @assert(third == 33)
    @assert(fourth == 44)
}

#test
{
    var point = DestructPair{x: 51, y: 52}
    var first:  s32
    var second: s32
    #[Swag.Safety(.Overflow, false)]
    {y: second, x: first} = point
    @assert(first == 51)
    @assert(second == 52)

    first  = 0
    second = 0
    if true do
        {x: first, y: second} = point
    @assert(first == 51)
    @assert(second == 52)

    first  = 0
    second = 0
    #static if true do
        {y: second, x: first} = point
    @assert(first == 51)
    @assert(second == 52)

    {x: point.y, y: point.x} = point
    @assert(point.x == 52)
    @assert(point.y == 51)
}

#test
{
    var namedThenUnnamed = {x: 61's32, 62's32}
    var first:  s32
    var second: s32
    {item1: second, x: first} = namedThenUnnamed
    @assert(first == 61)
    @assert(second == 62)

    var unnamedThenNamed = {71's32, y: 72's32}
    {y: second, item0: first} = unnamedThenNamed
    @assert(first == 71)
    @assert(second == 72)
}

#test
{
    var first:  s32
    var second: s32
    {first, second} = {81, 82}
    @assert(first == 81)
    @assert(second == 82)

    {x: first, item1: second} = {x: 83, 84}
    @assert(first == 83)
    @assert(second == 84)

    {item0: first, y: second} = {85, y: 86}
    @assert(first == 85)
    @assert(second == 86)
}

#test
{
    var first:  u32
    var second: u32
    {first, second} = jitMakeAssignDestructRet(11, 22)
    @assert(first == 11)
    @assert(second == 22)
}

#test
{
    var second: u32
    {?, second} = jitMakeAssignDestructRet(33, 44)
    @assert(second == 44)
}

#test
{
    var first:  u32 = 7
    var second: u32
    {first, second} = jitMakeAssignDestructRet(first + 1, first + 2)
    @assert(first == 8)
    @assert(second == 9)
}

#test
{
    var first:  u32
    var second: u32
    {first, second} = jitMakeAnonymousAssignDestructRet(55, 66)
    @assert(first == 55)
    @assert(second == 66)
}

#test
{
    var second: u32
    {?, second} = jitMakeAnonymousAssignDestructRet(77, 88)
    @assert(second == 88)
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

    @assert(run() == 33)
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
    @assert(nextLeaf == 7)
    @assert(sumLeaf == 33)

    let {nextBranch, sumBranch} = read(data[to], 7)
    @assert(nextBranch == 13)
    @assert(sumBranch == 0)

    var total: u32
    {?, total} = read(data[to], 0)
    @assert(total == 66)
}
