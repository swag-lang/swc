#global fileprivate

struct(A, B) Pair
{
    first: A
    second: B
}

struct Box
{
    value: s32
}

impl Box
{
    mtd(T) pairWith(other: T)->Pair'(s32, T)
    {
        return {first: .value, second: other}
    }

    mtd(T, const Mult: s32) tagged(other: T)->Pair'(T, s32)
    {
        return {first: other, second: Mult}
    }
}

#test
{
    var box = Box{value: 42}
    let pair = box.pairWith(0'u8)
    let tagged = box.tagged'(string, 3)("ok")

    #assert(#typeof(pair) == Pair'(s32, u8))
    #assert(#typeof(pair.first) == s32)
    #assert(#typeof(pair.second) == u8)
    #assert(#typeof(tagged) == Pair'(string, s32))
    #assert(#typeof(tagged.first) == string)
    #assert(#typeof(tagged.second) == s32)
}
