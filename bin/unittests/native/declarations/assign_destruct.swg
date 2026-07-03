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
    var result: retval = undefined
    result.first  = first
    result.second = second
    return result
}

#test
{
    var s: Pair
    var a: s32
    var b: bool
    (a, b) = s
    @assert(a == 0)
    @assert(!b)
}

#test
{
    var s: Pair
    var a: s32
    (a, ?) = s
    @assert(a == 0)
}

#test
{
    var first:  u32
    var second: u32
    (first, second) = nativeMakeAssignDestructRet(11, 22)
    @assert(first == 11)
    @assert(second == 22)
}

#test
{
    var second: u32
    (?, second) = nativeMakeAssignDestructRet(33, 44)
    @assert(second == 44)
}

#test
{
    var first:  u32 = 7
    var second: u32
    (first, second) = nativeMakeAssignDestructRet(first + 1, first + 2)
    @assert(first == 8)
    @assert(second == 9)
}

#test
{
    var first:  u32
    var second: u32
    (first, second) = nativeMakeAnonymousAssignDestructRet(55, 66)
    @assert(first == 55)
    @assert(second == 66)
}

#test
{
    var second: u32
    (?, second) = nativeMakeAnonymousAssignDestructRet(77, 88)
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
            (next, sum) = read(value + 1)
            return {next, sum + value}
        }

        var total: u32
        (?, total) = read(1)
        return total
    }

    @assert(run() == 33)
}

#test
{
    let data: [16] u32 = [2, 3, 0, 3, 10, 11, 12, 1, 1, 0, 1, 99, 2, 1, 1, 2]

    func read(n: const [..] u32, s: u32)->{ next, sum: u32 }
    {
        var start = s
        let (nc, nm) = {n[start], n[start + 1]}
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
            (start, sum) = read(n, start)
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

    let (nextLeaf, sumLeaf) = read(data[ to ], 2)
    @assert(nextLeaf == 7)
    @assert(sumLeaf == 33)

    let (nextBranch, sumBranch) = read(data[ to ], 7)
    @assert(nextBranch == 13)
    @assert(sumBranch == 0)

    var total: u32
    (?, total) = read(data[ to ], 0)
    @assert(total == 66)
}
