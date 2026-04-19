#global fileprivate

enum TestKey: u32
{
    None
    A
    B
}

func takesKey(key: TestKey)->u32
{
    return cast(u32) key
}

#test
{
    let a = cast(TestKey) 1'u8
    let b = cast(TestKey) 2'u32

    @assert(a == TestKey.A)
    @assert(b == TestKey.B)
    @assert(takesKey(cast(TestKey) 0'u32) == 0'u32)
}
