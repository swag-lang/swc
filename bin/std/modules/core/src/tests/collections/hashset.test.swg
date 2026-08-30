#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertStringSetHas(values: HashSet'String, expected: string)->bool
{
    for value in values
    {
        if value.toString() == expected do
            return true
    }

    return false
}

func assertReverseIntSetIteration(values: HashSet's32)->bool
{
    var forward: Array's32
    for value in values do
        forward.add(value)

    var reverse: Array's32
    for value in values.reversed() do
        reverse.add(value)

    if forward.count != reverse.count do
        return false

    for i in forward.count
    {
        if forward[i] != reverse[reverse.count - i - 1] do
            return false
    }

    return true
}

#test
{
    var values: HashSet's32
    Swag.assert(values.count == 0)
    Swag.assert(!values.contains(1))

    values.add(1)
    values.add(3)
    values.add(1)

    Swag.assert(values.count == 2)
    Swag.assert(values.contains(1))
    Swag.assert(values.contains(3))

    var sum = 0
    for value in values do
        sum += value
    Swag.assert(sum == 4)
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)
    values.add(3)
    values.add(4)

    Swag.assert(assertReverseIntSetIteration(values))
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)
    values.add(3)

    values.remove(2)
    Swag.assert(!values.contains(2))
    Swag.assert(values.count == 2)

    values.add(2)
    Swag.assert(values.contains(2))
    Swag.assert(values.count == 3)

    values.clear()
    Swag.assert(values.count == 0)
    Swag.assert(!values.contains(1))
    Swag.assert(!values.contains(2))
    Swag.assert(!values.contains(3))
}

#test
{
    var moved: String = "beta"

    var values: HashSet'String
    values.add("alpha")
    values.add(#move moved)

    Swag.assert(values.count == 2)
    Swag.assert(values.contains("alpha"))
    Swag.assert(values.contains("beta"))
    Swag.assert(assertStringSetHas(values, "alpha"))
    Swag.assert(assertStringSetHas(values, "beta"))
}

#test
{
    var original: HashSet'String
    original.add("alpha")
    original.add("beta")
    original.remove("alpha")

    var copy = original
    copy.add("gamma")
    copy.add("alpha")

    Swag.assert(!assertStringSetHas(original, "alpha"))
    Swag.assert(assertStringSetHas(original, "beta"))

    Swag.assert(assertStringSetHas(copy, "alpha"))
    Swag.assert(assertStringSetHas(copy, "beta"))
    Swag.assert(assertStringSetHas(copy, "gamma"))
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)

    let seed: [1] s32 = [3]
    values = seed

    Swag.assert(values.count == 1)
    Swag.assert(!values.contains(1))
    Swag.assert(!values.contains(2))
    Swag.assert(values.contains(3))
}

#test
{
    var values: HashSet's32
    values.reserve(33)

    values.add(10)
    values.add(42)
    values.add(74)

    Swag.assert(values.capacity >= 33)
    Swag.assert(values.contains(10))
    Swag.assert(values.contains(42))
    Swag.assert(values.contains(74))
}

#test
{
    var values: HashSet's32

    Swag.assert(values.toggle(10))
    Swag.assert(values.contains(10))
    Swag.assert(values.count == 1)

    Swag.assert(!values.toggle(10))
    Swag.assert(!values.contains(10))
    Swag.assert(values.count == 0)

    values.add(42)
    Swag.assert(!values.toggle(42))
    Swag.assert(!values.contains(42))
    Swag.assert(values.count == 0)
}
