// Disabled on purpose: this HashTable coverage exposed a compiler bug around contextual
// specialization of generic associated types inside compiler ops like `#sizeof(...)`.
// Keep the independent compiler regression in `bin/tests/jit/compiler/generic_sizeof_associated_type.swg`
// until the core path is known to run in a few seconds again.
#global #if false//#command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertTableStringValue(table: const &HashTable'(string, String), key: string, expected: string)->bool
{
    let entry = table.tryFind(key)
    return entry != null and entry.value == expected and @countof(entry.value) == @countof(expected)
}

#test
{
    var table: HashTable'(s32, s32)
    @assert(table.count == 0)
    @assert(!table.contains(1))
    @assert(table.tryFind(1) == null)

    table.add(1, 10)

    var movedValue: s32 = 20
    table.add(2, moveref &movedValue)

    table[1] = 11
    table[3] = 30

    let slot4 = table.findOrAdd(4)
    slot4.value = 40

    @assert(table.count == 4)
    @assert(table.contains(2))
    @assert(table.get(9, 99) == 99)
    @assert(table[1] == 11)

    let entryTwo = table.find(2)
    entryTwo.value += 2
    @assert(table[2] == 22)

    var sumKeys = 0
    var sumValues = 0
    foreach key, value in table
    {
        #assert(#typeof(key) == s32)
        #assert(#typeof(value) == s32)
        sumKeys += key
        sumValues += value
    }

    @assert(sumKeys == 10)
    @assert(sumValues == 103)

    table.remove(2)
    @assert(!table.contains(2))
    @assert(table.count == 3)

    table.add(2, 200)
    table.add(2, 999, false)
    @assert(table.count == 4)
    @assert(table[2] == 200)

    table.clear()
    @assert(table.count == 0)
    @assert(!table.contains(1))
    @assert(!table.contains(2))
}

#test
{
    var original: HashTable'(string, String)
    original.add("alpha", "one")
    original.add("beta", "two")

    var copy = original
    copy["alpha"] = "uno"
    copy.findOrAdd("gamma").value = "three"

    @assert(assertTableStringValue(original, "alpha", "one"))
    @assert(assertTableStringValue(original, "beta", "two"))
    @assert(original.tryFind("gamma") == null)

    @assert(assertTableStringValue(copy, "alpha", "uno"))
    @assert(assertTableStringValue(copy, "beta", "two"))
    @assert(assertTableStringValue(copy, "gamma", "three"))
}
