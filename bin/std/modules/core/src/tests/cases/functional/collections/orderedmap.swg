#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertOrderedMapBorrowTypes(map: *OrderedMap'(s32, String))
{
    for &key, value in map[]
    {
        #assert(#typeof(key) == const *s32)
        #assert(#typeof(value) == *String)
    }

    for &key, value in map[].reversed()
    {
        #assert(#typeof(key) == const *s32)
        #assert(#typeof(value) == *String)
    }
}

struct OrderedMapKey
{
    rank: s32
}

struct OrderedMapEquivalentKey
{
    rank:  s32
    label: s32
}

#test
{
    var map: OrderedMap'(s32, String)
    map.initialize(func(left, right: const *s32)->s32 => left[] <=> right[])
    map.add(30, "thirty")
    map.add(10, "ten")
    map.add(20, "twenty")
    map[20] = "TWENTY"

    assertOrderedMapBorrowTypes(&map)

    var keyCode = 0
    for key, value, index in map
    {
        keyCode = keyCode * 100 + key
        if index == 1 do
            Swag.require(value[] == "TWENTY")
    }

    Swag.require(keyCode == 102030)
    Swag.require(map.count == 3 and map.capacity() >= 3)
    Swag.require(map.lowerBound(20) == 1)
    Swag.require(map.upperBound(20) == 2)
    Swag.require(map.contains(10) and not map.contains(11))
    Swag.require(map.find(30).value == "thirty")

    let middle = map.range(15, 30)
    Swag.require(middle.count == 1 and middle[0].key == 20 and middle[0].value == "TWENTY")
    Swag.require((map.range(30, 10)).count == 0)

    Swag.require(map.remove(20))
    Swag.require(not map.remove(20))
    Swag.require(map.count == 2)
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

    Swag.require(forward == 321)
    Swag.require(reverse == 123)
}

#test
{
    var map: OrderedMap'(OrderedMapKey, s32)
    map.initialize(func(left, right: const *OrderedMapKey)->s32 => left.rank <=> right.rank)
    map.add({rank: 4}, 40)
    map.add({rank: 1}, 10)

    Swag.require(map.find({rank: 1}).value == 10)

    var copy = map
    copy.add({rank: 2}, 20)
    Swag.require(map.count == 2 and copy.count == 3)
}

#test
{
    var map: OrderedMap'(OrderedMapEquivalentKey, s32)
    map.initialize(func(left, right: const *OrderedMapEquivalentKey)->s32 => left.rank <=> right.rank)
    map.add({rank: 1, label: 10}, 100)
    let entry = map.add({rank: 1, label: 20}, 200)

    Swag.require(map.count == 1)
    Swag.require(entry.key.label == 10 and entry.value == 200)
}

// Reserving less storage preserves the elements and their existing capacity.
#test
{
    var map = OrderedMap'(s32, String).create(func(left, right: const *s32)->s32 => left[] <=> right[])
    map.add(42, "kept")
    let capacity = map.capacity()
    map.reserve(0)
    Swag.require(map.count == 1 and map.capacity() == capacity)
    Swag.require(map.find(42).value == "kept")
}
