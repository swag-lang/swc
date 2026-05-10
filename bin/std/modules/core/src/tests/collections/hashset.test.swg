#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertStringSetHas(values: const &HashSet'String, expected: string)->bool
{
    foreach value in values
    {
        if value.toString() == expected do
            return true
    }

    return false
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
    foreach value in values do
        sum += value
    @assert(sum == 4)
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
    values.add(moveref &moved)

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
