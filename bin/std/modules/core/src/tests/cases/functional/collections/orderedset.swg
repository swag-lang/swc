#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertOrderedSetKeysAreReadOnly(values: *OrderedSet's32)
{
    for &key in values[]
    {
        #assert(#typeof(key) == const *s32)
    }

    for &key in values[].reversed()
    {
        #assert(#typeof(key) == const *s32)
    }
}

#test
{
    var set: OrderedSet's32
    set.initialize(func(left, right: const *s32)->s32 => left[] <=> right[])
    Swag.require(set.add(4))
    Swag.require(set.add(1))
    Swag.require(set.add(3))
    Swag.require(not set.add(3))
    Swag.require(set.add(2))

    assertOrderedSetKeysAreReadOnly(&set)

    var code = 0
    for key in set do
        code = code * 10 + key
    Swag.require(code == 1234)

    var reverse = 0
    for key in set.reversed() do
        reverse = reverse * 10 + key
    Swag.require(reverse == 4321)

    Swag.require(set.lowerBound(2) == 1)
    Swag.require(set.upperBound(2) == 2)
    let middle = set.range(2, 4)
    Swag.require(middle.count == 2 and middle[0] == 2 and middle[1] == 3)
    Swag.require(set.remove(2) and not set.remove(2))
    Swag.require(not set.contains(2) and set.count == 3)
}

#test
{
    var set: OrderedSet'String
    set.initialize(func(left, right: const *String)->s32 => Utf8.compare(right[], left[]))
    set.add("alpha")
    set.add("gamma")
    set.add("beta")

    var result: String
    for key in set do
        result += key[]
    Swag.require(result == "gammabetaalpha")

    var copy = set
    discard copy.remove("beta")
    Swag.require(set.count == 3 and copy.count == 2)
}

// Reserving less storage preserves the elements and their existing capacity.
#test
{
    var set = OrderedSet's32.create(func(left, right: const *s32)->s32 => left[] <=> right[])
    set.add(42)
    let capacity = set.capacity()
    set.reserve(0)
    Swag.require(set.count == 1 and set.capacity() == capacity)
    Swag.require(set.contains(42))
}
