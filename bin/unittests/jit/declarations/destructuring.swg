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
    return {first: first, second: second}
}

func jitMakeAssignDestructRet(first, second: u32)->JitAssignDestructRet
{
    var result: #returntype
    result.first  = first
    result.second = second
    return result
}

#test
{
    let pair         = DestructPair{x: 10, y: 20}
    let {x: a, y: b} = pair
    Swag.require(a == 10)
    Swag.require(b == 20)
}

#test
{
    var pair         = DestructPair{x: 10, y: 20}
    var {x: a, y: b} = pair
    Swag.require(a == 10)
    Swag.require(b == 20)
    a = 100
    b = 200
    Swag.require(a == 100)
    Swag.require(b == 200)
}

#test
{
    let {x: a, y: b} = {x: 1, y: 2}
    Swag.require(a == 1)
    Swag.require(b == 2)
}

#test
{
    var {x: a, y: b} = {x: 1, y: 2}
    Swag.require(a == 1)
    Swag.require(b == 2)
    a = 10
    b = 20
    Swag.require(a == 10)
    Swag.require(b == 20)
}

#test
{
    let {x: a, y: b, z: c} = {x: true, y: 42's32, z: 3.14}
    Swag.require(a == true)
    Swag.require(b == 42)
    Swag.require(c == 3.14)
}

#test
{
    var {x: a, y: b} = {x: true, y: false}
    Swag.require(a == true)
    Swag.require(b == false)
    a = false
    Swag.require(a == false)
}

#test
{
    let t = {x: 1.0, y: 2.0, z: 3.0}
    discard t
    let {x: a, y: _} = {x: 10, y: 20}
    Swag.require(a == 10)
    let {x: _, y: b} = {x: 10, y: 20}
    Swag.require(b == 20)
}

#test
{
    let t = {a: 1's32, b: 2's32, c: 3's32}
    let {a: _, b: _, c} = t
    Swag.require(c == 3)
    let {a: x, b: _, c: _} = t
    Swag.require(x == 1)
    let {a: _, b: y, c: _} = t
    Swag.require(y == 2)
}

#test
{
    let point = DestructPair{x: 10, y: 20}
    let {y: second, x: first} = point
    Swag.require(first == 10)
    Swag.require(second == 20)

    let {x: onlyX} = point
    Swag.require(onlyX == 10)
}

#test
{
    let namedThenUnnamed = {x: 11's32, item1: 22's32}
    let {item1: second, x: first} = namedThenUnnamed
    Swag.require(first == 11)
    Swag.require(second == 22)

    let unnamedThenNamed = {item0: 33's32, y: 44's32}
    let {y: fourth, item0: third} = unnamedThenNamed
    Swag.require(third == 33)
    Swag.require(fourth == 44)
}

#test
{
    var point = DestructPair{x: 51, y: 52}
    var first:  s32
    var second: s32
    #[Swag.Safety(.Overflow, false)]
    {y: second, x: first} = point
    Swag.require(first == 51)
    Swag.require(second == 52)

    first  = 0
    second = 0
    if true do
        {x: first, y: second} = point
    Swag.require(first == 51)
    Swag.require(second == 52)

    first  = 0
    second = 0
    #static if true do
        {y: second, x: first} = point
    Swag.require(first == 51)
    Swag.require(second == 52)

    {x: point.y, y: point.x} = point
    Swag.require(point.x == 52)
    Swag.require(point.y == 51)
}

#test
{
    var namedThenUnnamed = {x: 61's32, item1: 62's32}
    var first:  s32
    var second: s32
    {item1: second, x: first} = namedThenUnnamed
    Swag.require(first == 61)
    Swag.require(second == 62)

    var unnamedThenNamed = {item0: 71's32, y: 72's32}
    {y: second, item0: first} = unnamedThenNamed
    Swag.require(first == 71)
    Swag.require(second == 72)
}

#test
{
    var first:  s32
    var second: s32
    (first, second) = (81, 82)
    Swag.require(first == 81)
    Swag.require(second == 82)

    {x: first, item1: second} = {x: 83, item1: 84}
    Swag.require(first == 83)
    Swag.require(second == 84)

    {item0: first, y: second} = {item0: 85, y: 86}
    Swag.require(first == 85)
    Swag.require(second == 86)
}

#test
{
    var first:  u32
    var second: u32
    {first, second} = jitMakeAssignDestructRet(11, 22)
    Swag.require(first == 11)
    Swag.require(second == 22)
}

#test
{
    var second: u32
    {first: _, second} = jitMakeAssignDestructRet(33, 44)
    Swag.require(second == 44)
}

#test
{
    var first:  u32 = 7
    var second: u32
    {first, second} = jitMakeAssignDestructRet(first + 1, first + 2)
    Swag.require(first == 8)
    Swag.require(second == 9)
}

#test
{
    var first:  u32
    var second: u32
    {first, second} = jitMakeAnonymousAssignDestructRet(55, 66)
    Swag.require(first == 55)
    Swag.require(second == 66)
}

#test
{
    var second: u32
    {first: _, second} = jitMakeAnonymousAssignDestructRet(77, 88)
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
