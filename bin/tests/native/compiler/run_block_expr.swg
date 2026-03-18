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

const PersistentText: string = #run
{
    var data: [3] u8
    data[0] = 'a'
    data[1] = 'b'
    data[2] = data[1] + 1
    return cast(string) data
}

const PersistentBytes: const [..] u8 = #run
{
    var data: [4] u8
    data[0] = 1
    data[1] = 2
    data[2] = 3
    data[3] = 4
    return cast(const [..] u8) data
}

struct TextHolder
{
    text: string
}

struct BytesHolder
{
    bytes: const [..] u8
}

struct AnyPair
{
    item: any
    other: any
}

const PersistentTextHolder: TextHolder = #run
{
    var data: [3] u8
    data[0] = 'a'
    data[1] = 'b'
    data[2] = data[1] + 1

    var holder: TextHolder
    holder.text = cast(string) data
    return holder
}

const PersistentStringArray: [1] string = #run
{
    var data: [3] u8
    data[0] = 'a'
    data[1] = 'b'
    data[2] = data[1] + 1

    var values: [1] string
    values[0] = cast(string) data
    return values
}

const PersistentAnyPair: AnyPair = #run
{
    var pair: AnyPair
    pair.item = "abc"
    pair.other = "def"
    return pair
}

const PersistentBytesHolder: BytesHolder = #run
{
    var data: [4] u8
    data[0] = 1
    data[1] = 2
    data[2] = 3
    data[3] = 4

    var holder: BytesHolder
    holder.bytes = cast(const [..] u8) data
    return holder
}

#[Swag.Compiler]
func assertCompilerOnlyRunCall(value: string)
{
    @assert(value == "inside compiler-only run call")
}

func functionScopedRunBlock()
{
    #run
    {
        #assert(#curlocation.funcName == "functionScopedRunBlock")
    }
}

func functionScopedCompilerOnlyRunCall()
{
    #run
    {
        let value = "inside compiler-only run call"
        assertCompilerOnlyRunCall(value)
    }
}

func functionScopedShortCompilerOnlyRunCall()
{
    #run assertCompilerOnlyRunCall("inside compiler-only run call")
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
#assert(PersistentText == "abc")
#assert(PersistentTextHolder.text == "abc")
#assert(PersistentStringArray[0] == "abc")
#assert(cast(string) PersistentAnyPair.item == "abc")
#assert(cast(string) PersistentAnyPair.other == "def")
#assert(@countof(PersistentBytes) == 4)
#assert(PersistentBytes[0] == 1)
#assert(PersistentBytes[3] == 4)
#assert(@countof(PersistentBytesHolder.bytes) == 4)
#assert(PersistentBytesHolder.bytes[0] == 1)
#assert(PersistentBytesHolder.bytes[3] == 4)

#test
{
    functionScopedRunBlock()
    functionScopedCompilerOnlyRunCall()
    functionScopedShortCompilerOnlyRunCall()

    let values = #run
    {
        var items: [2] any
        items[0] = "first"
        items[1] = "second"
        return items
    }

    @assert(cast(string) values[0] == "first")
    @assert(cast(string) values[1] == "second")
}
