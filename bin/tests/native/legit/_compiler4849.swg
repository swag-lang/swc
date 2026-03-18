#global fileprivate
#global skip

const MyString: string = #run
{
    var str: [3] u8
    str[0] = 'a'
    str[1] = 'b'
    str[2] = str[1] + 1
    return cast(string) str
}

#assert(MyString == "abc")

struct Carrier
{
    item: any
    other: any
}

#test
{
    let value = #run
    {
        var payload: Carrier
        payload.item = "abc"
        payload.other = "def"
        return payload
    }

    let values = #run
    {
        var words: [2] any
        words[0] = "first"
        words[1] = "second"
        return words
    }

    @assert(cast(string) value.item == "abc")
    @assert(cast(string) value.other == "def")
    @assert(cast(string) values[0] == "first")
    @assert(cast(string) values[1] == "second")
}
