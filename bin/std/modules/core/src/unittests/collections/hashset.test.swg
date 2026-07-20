#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertStringSetHas(values: const &HashSet'String, expected: string)->bool
{
    for value in values
    {
        if value.toString() == expected do
            return true
    }

    return false
}

func assertReverseIntSetIteration(values: const &HashSet's32)->bool
{
    var forward: Array's32
    for value in values do
        forward.add(value)

    var reverse: Array's32
    for #reverse value in values do
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
    @assert(values.count == 0)
    @assert(!values.contains(1))

    values.add(1)
    values.add(3)
    values.add(1)

    @assert(values.count == 2)
    @assert(values.contains(1))
    @assert(values.contains(3))

    var sum = 0
    for value in values do
        sum += value
    @assert(sum == 4)
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)
    values.add(3)
    values.add(4)

    @assert(assertReverseIntSetIteration(values))
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)
    values.add(3)

    values.remove(2)
    @assert(!values.contains(2))
    @assert(values.count == 2)

    values.add(2)
    @assert(values.contains(2))
    @assert(values.count == 3)

    values.clear()
    @assert(values.count == 0)
    @assert(!values.contains(1))
    @assert(!values.contains(2))
    @assert(!values.contains(3))
}

#test
{
    var moved: String = "beta"

    var values: HashSet'String
    values.add("alpha")
    values.add(#move moved)

    @assert(values.count == 2)
    @assert(values.contains("alpha"))
    @assert(values.contains("beta"))
    @assert(assertStringSetHas(values, "alpha"))
    @assert(assertStringSetHas(values, "beta"))
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

    @assert(!assertStringSetHas(original, "alpha"))
    @assert(assertStringSetHas(original, "beta"))

    @assert(assertStringSetHas(copy, "alpha"))
    @assert(assertStringSetHas(copy, "beta"))
    @assert(assertStringSetHas(copy, "gamma"))
}

#test
{
    var values: HashSet's32
    values.add(1)
    values.add(2)

    let seed: [1] s32 = [3]
    values = seed

    @assert(values.count == 1)
    @assert(!values.contains(1))
    @assert(!values.contains(2))
    @assert(values.contains(3))
}

#test
{
    var values: HashSet's32
    values.reserve(33)

    values.add(10)
    values.add(42)
    values.add(74)

    @assert(values.capacity >= 33)
    @assert(values.contains(10))
    @assert(values.contains(42))
    @assert(values.contains(74))
}

#test
{
    var values: HashSet's32

    @assert(values.toggleKey(10))
    @assert(values.contains(10))
    @assert(values.count == 1)

    @assert(!values.toggleKey(10))
    @assert(!values.contains(10))
    @assert(values.count == 0)

    values.add(42)
    @assert(!values.toggleKey(42))
    @assert(!values.contains(42))
    @assert(values.count == 0)
}
