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
    map.initialize(func(left, right: const *s32)->s32 => left[] <=> right[])
    map.add(30, "thirty")
    map.add(10, "ten")
    map.add(20, "twenty")
    map[20] = "TWENTY"

    var keyCode = 0
    for key, value, index in map
    {
        keyCode = keyCode * 100 + key
        if index == 1 do
            Swag.assert(value[] == "TWENTY")
    }

    Swag.assert(keyCode == 102030)
    Swag.assert(map.count == 3 and map.capacity() >= 3)
    Swag.assert(map.lowerBound(20) == 1)
    Swag.assert(map.upperBound(20) == 2)
    Swag.assert(map.contains(10) and !map.contains(11))
    Swag.assert(map.find(30).value == "thirty")

    let middle = map.range(15, 30)
    Swag.assert(middle.count == 1 and middle[0].key == 20 and middle[0].value == "TWENTY")
    Swag.assert((map.range(30, 10)).count == 0)

    Swag.assert(map.remove(20))
    Swag.assert(!map.remove(20))
    Swag.assert(map.count == 2)
}

#test
{
    var map: OrderedMap'(s32, s32)
    map.initialize(func(left, right: const *s32)->s32 => right[] <=> left[])
    map.add(1, 10)
    map.add(3, 30)
    map.add(2, 20)

    var forward = 0
    for key in map do
        forward = forward * 10 + key
    var reverse = 0
    for key in map.reversed() do
        reverse = reverse * 10 + key

    Swag.assert(forward == 321)
    Swag.assert(reverse == 123)
}

#test
{
    var map: OrderedMap'(OrderedMapKey, s32)
    map.initialize(func(left, right: const *OrderedMapKey)->s32 => left.rank <=> right.rank)
    map.add({rank: 4}, 40)
    map.add({rank: 1}, 10)

    Swag.assert(map.find(OrderedMapKey{rank: 1}).value == 10)

    var copy = map
    copy.add({rank: 2}, 20)
    Swag.assert(map.count == 2 and copy.count == 3)
}
