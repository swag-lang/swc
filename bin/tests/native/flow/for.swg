#global fileprivate // 

struct CountedLoop
{
    count: u64
}

struct FixedCountedLoop
{
}

impl CountedLoop
{
    mtd opCount() => me.count
}

impl FixedCountedLoop
{
    mtd opCount() => 4'u64
}

#test
{
    var count = 0
    for 3
    {
        var x = 0
        count += 1
    }
    @assert(count == 3)
}

#test
{
    var sum = 0
    for i in 3
    {
        var x = i
        sum += cast(s32) i
    }
    @assert(sum == 3)
}

#test
{
    var first = -1
    var last = -1
    var sum = 0
    for #reverse i in 3
    {
        var x = i
        if first == -1 do
            first = cast(s32) i
        last = cast(s32) i
        sum += cast(s32) i
    }
    @assert(first == 2)
    @assert(last == 0)
    @assert(sum == 3)
}






#test
{
    var count = 0
    for #reverse 5
    {
        var x = 0
        count += 1
    }
    @assert(count == 5)
}

#test
{
    var sum = 0
    for #reverse i in 5
    {
        var x = i
        sum += cast(s32) i
    }
    @assert(sum == 10)
}

#test
{
    var count = 0
    for
    {
        count += 1
        break
    }
    @assert(count == 1)
}

#test
{
    var count = 0
    for
    {
        count += 1
        break
    }
    @assert(count == 1)
}

#test
{
    var sum = 0
    for i in 1 to 5
    {
        var x = i
        sum += cast(s32) i
    }
    @assert(sum == 15)
}

#test
{
    var sum = 0
    for i in 1 until 5
    {
        var x = i
        sum += cast(s32) i
    }
    @assert(sum == 10)
}

#test
{
    var first = -1
    var last = -1
    var sum = 0
    for #reverse i in 1 to 5
    {
        var x = i
        if first == -1 do
            first = cast(s32) i
        last = cast(s32) i
        sum += cast(s32) i
    }
    @assert(first == 5)
    @assert(last == 1)
    @assert(sum == 15)
}

#test
{
    var first = -1
    var last = -1
    var sum = 0
    for #reverse i in 1 until 5
    {
        var x = i
        if first == -1 do
            first = cast(s32) i
        last = cast(s32) i
        sum += cast(s32) i
    }
    @assert(first == 4)
    @assert(last == 1)
    @assert(sum == 10)
}

#test
{
    var count = 0
    var sum = 0
    for i in 10 where i > 3
    {
        var x = i
        count += 1
        sum += cast(s32) i
    }
    @assert(count == 6)
    @assert(sum == 39)
}

#test
{
    let value0 = CountedLoop{count: 4}
    let value1 = CountedLoop{count: 0}
    var count0 = 0
    var count1 = 0

    for value0 do
        count0 += 1

    for value1 do
        count1 += 1

    @assert(count0 == 4)
    @assert(count1 == 0)
}

#test
{
    let value = FixedCountedLoop{}
    var count = 0
    var sum = 0

    for value do
        count += 1

    for i in value do
        sum += cast(s32) i

    @assert(count == 4)
    @assert(sum == 6)
}

#test
{
    var count = 0
    var sum = 0
    for i in 0 to 10 where i % 2 == 0
    {
        var x = i
        count += 1
        sum += cast(s32) i
    }
    @assert(count == 6)
    @assert(sum == 30)
}

#test
{
    var count = 0
    var sum = 0
    for i in 0 until 10 where i > 5
    {
        var x = i
        count += 1
        sum += cast(s32) i
    }
    @assert(count == 4)
    @assert(sum == 30)
}

#test
{
    var first = -1
    var last = -1
    var count = 0
    for #reverse i in 10 where i < 5
    {
        var x = i
        if first == -1 do
            first = cast(s32) i
        last = cast(s32) i
        count += 1
    }
    @assert(first == 4)
    @assert(last == 0)
    @assert(count == 5)
}

#test
{
    var count = 0
    for i in 3
    {
        for j in 3
        {
            var x = i
            var y = j
            count += 1
        }
    }
    @assert(count == 9)
}

#test
{
    var count = 0
    var last = -1
    for i in 1
    {
        for j in 1
        {
            var x = j
            last = cast(s32) x
            count += 1
        }
    }
    @assert(count == 1)
    @assert(last == 0)
}

#test
{
    var count = 0
    for 10
    {
        var x = 0
        count += 1
        break
    }
    @assert(count == 1)
}

#test
{
    var sum = 0
    for i in 10
    {
        var x = i
        sum += cast(s32) i
        continue
        var y = 0 // Unreachable code is allowed
    }
    @assert(sum == 45)
}

#test
{
    var outerCount = 0
    var innerCount = 0
    for 2
    {
        for 2
        {
            innerCount += 1
            break
        }
        var x = 0
        outerCount += 1
    }
    @assert(outerCount == 2)
    @assert(innerCount == 2)
}

#test
{
    var arr: [5]s32 = [1, 2, 3, 4, 5]
    var count = 0
    for arr
    {
        var x = 0
        count += 1
    }
    @assert(count == 5)
}

#test
{
    var arr: [3]s32 = [1, 2, 3]
    var sum = 0
    for i in arr
    {
        var x = i
        sum += cast(s32) x
    }
    @assert(sum == 3)
}

#test
{
    var count = 0
    for 3
    {
        count += 1
    }
    @assert(count == 3)
}

#test
{
    var sum = 0
    for i in 0 to 3
    {
        sum += cast(s32) i
    }
    @assert(sum == 6)
}

#test
{
    var count = 0
    for 3 do
        count += 1
    @assert(count == 3)
}

#test
{
    var sum = 0
    for i in 3 do
        sum += cast(s32) i
    @assert(sum == 3)
}

#test
{
    var count = 0
    for i in 1
    {
        count += 1
    }

    for i in 1
    {
        count += 1
    }
    @assert(count == 2)
}

#test
{
    var i = 5
    var count = 0
    for i in 3
    {
        var x = i // shadows outer i
        count += 1
    }
    @assert(i == 5)
    @assert(count == 3)
}

#test
{
    var sum = 0
    for i in 5 where i > 0
    {
        var x = i
        sum += cast(s32) i
    }
    @assert(sum == 10)
}

#test
{
    var str: string
    var count0 = 0
    for it in @countof(str) { count0 += 1 }
    var v: u32
    var count1 = 0
    for it in v { count1 += 1 }
    var v1: s32
    @assert(count0 == 0)
    @assert(count1 == 0)
    @assert(v1 == 0)
}

#test
{
    var sum = 0
    for i in 1 to 3
    {
        switch i
        {
            case 1:
                sum += cast(s32) @index
            default:
                sum += cast(s32) @index
        }
    }

    @assert(sum == 6)
}

#test
{
    #[Swag.EnumFlags]
    enum Bits: u32 { A, B, C }

    var count = 0
    var sum = 0
    for idx in Bits
    {
        #assert(#typeof(idx) == u64)
        count += 1
        sum += cast(s32) idx
    }

    @assert(count == 3)
    @assert(sum == 3)
}
