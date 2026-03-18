#global fileprivate

const ScalarValue = #run
{
    let base = 20
    return (base + 1) * 2
}

const PowerOfTwo: [4] s32 = #run
{
    var arr: [4] s32
    for i in arr do
        arr[i] = 1 << cast(u32) i
    return arr
}

const DeducePowerOfTwo = #run
{
    return [1, 2, 3, 4]
}

struct AnyPair
{
    item: any
    other: any
}

const PersistentAnyPair: AnyPair = #run
{
    var pair: AnyPair
    pair.item = "abc"
    pair.other = "def"
    return pair
}

const PersistentAnyArray: [2] any = #run
{
    var values: [2] any
    values[0] = "first"
    values[1] = "second"
    return values
}

#assert(#typeof(ScalarValue) == s32)
#assert(ScalarValue == 42)
#assert(#typeof(PowerOfTwo) == [4] s32)
#assert(PowerOfTwo[0] == 1)
#assert(PowerOfTwo[1] == 2)
#assert(PowerOfTwo[2] == 4)
#assert(PowerOfTwo[3] == 8)
#assert(#typeof(DeducePowerOfTwo) == [4] s32)
#assert(DeducePowerOfTwo[0] == 1)
#assert(DeducePowerOfTwo[3] == 4)
#assert(cast(string) PersistentAnyPair.item == "abc")
#assert(cast(string) PersistentAnyPair.other == "def")
#assert(cast(string) PersistentAnyArray[0] == "first")
#assert(cast(string) PersistentAnyArray[1] == "second")

#test
{
    let value = #run
    {
        var pair: AnyPair
        pair.item = "abc"
        pair.other = "def"
        return pair
    }

    let values = #run
    {
        var items: [2] any
        items[0] = "first"
        items[1] = "second"
        return items
    }

    @assert(cast(string) value.item == "abc")
    @assert(cast(string) value.other == "def")
    @assert(cast(string) values[0] == "first")
    @assert(cast(string) values[1] == "second")
}
