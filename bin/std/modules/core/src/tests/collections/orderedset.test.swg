#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var set: OrderedSet's32
    set.initialize(func(left, right: const *s32)->s32 => left[] <=> right[])
    Swag.assert(set.add(4))
    Swag.assert(set.add(1))
    Swag.assert(set.add(3))
    Swag.assert(!set.add(3))
    Swag.assert(set.add(2))

    var code = 0
    for key in set do
        code = code * 10 + key
    Swag.assert(code == 1234)

    var reverse = 0
    for key in set.reversed() do
        reverse = reverse * 10 + key
    Swag.assert(reverse == 4321)

    Swag.assert(set.lowerBound(2) == 1)
    Swag.assert(set.upperBound(2) == 2)
    let middle = set.range(2, 4)
    Swag.assert(middle.count == 2 and middle[0] == 2 and middle[1] == 3)
    Swag.assert(set.remove(2) and !set.remove(2))
    Swag.assert(!set.contains(2) and set.count == 3)
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
    Swag.assert(result == "gammabetaalpha")

    var copy = set
    discard copy.remove("beta")
    Swag.assert(set.count == 3 and copy.count == 2)
}
