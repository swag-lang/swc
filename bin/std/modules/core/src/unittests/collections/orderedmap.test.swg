#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct OrderedMapKey
{
    rank: s32
}

#test
{
    var map: OrderedMap'(s32, String)
    map.initialize(func(left, right: const *s32)->s32 => dref left <=> dref right)
    map.add(30, "thirty")
    map.add(10, "ten")
    map.add(20, "twenty")
    map[20] = "TWENTY"

    var keyCode = 0
    for key, value, index in map
    {
        keyCode = keyCode * 100 + key
        if index == 1 do
            @assert(dref value == "TWENTY")
    }

    @assert(keyCode == 102030)
    @assert(map.count == 3 and map.capacity() >= 3)
    @assert(map.lowerBound(20) == 1)
    @assert(map.upperBound(20) == 2)
    @assert(map.contains(10) and !map.contains(11))
    @assert(map.find(30).value == "thirty")

    let middle = map.range(15, 30)
    @assert(@countof(middle) == 1 and middle[0].key == 20 and middle[0].value == "TWENTY")
    @assert(@countof(map.range(30, 10)) == 0)

    @assert(map.remove(20))
    @assert(!map.remove(20))
    @assert(map.count == 2)
}

#test
{
    var map: OrderedMap'(s32, s32)
    map.initialize(func(left, right: const *s32)->s32 => dref right <=> dref left)
    map.add(1, 10)
    map.add(3, 30)
    map.add(2, 20)

    var forward = 0
    for key in map do
        forward = forward * 10 + key
    var reverse = 0
    for key in map.reversed() do
        reverse = reverse * 10 + key

    @assert(forward == 321)
    @assert(reverse == 123)
}

#test
{
    var map: OrderedMap'(OrderedMapKey, s32)
    map.initialize(func(left, right: const *OrderedMapKey)->s32 => left.rank <=> right.rank)
    map.add({rank: 4}, 40)
    map.add({rank: 1}, 10)

    @assert(map.find(OrderedMapKey{rank: 1}).value == 10)

    var copy = map
    copy.add({rank: 2}, 20)
    @assert(map.count == 2 and copy.count == 3)
}
